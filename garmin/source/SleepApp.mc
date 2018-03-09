using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Sensor as Sensor;
using Toybox.Time as Time;
using Toybox.Communications as Comm;
using Toybox.Attention as Attention;
using Toybox.System as Sys;
using Toybox.Time.Gregorian as Calendar;
using Toybox.Math as Math;

// Globals

    var debug = true; var fakeTransmit = false; var beta = false;
    var notice = "";

    var dataTimer;
    // var secondTimer;
    // var messageTime = 0;
    // const messageLoop = 2000;
    var current_heartrate = 0;

    var now;
    var timecurrent = 0;
    var logtimestamp;

    var messageQueue = [];
    var deliveryInProgress = false;
    var deliveryErrorCount = 0;
    var deliveryPauseCount = 0;
    const MAX_DELIVERY_ERROR = 3;
    const MAX_DELIVERY_PAUSE = 20;

    var alarm_currently_active = false; // Is alarm currently ringing on phone?
    var exitTapped = false;
    var alarmViewActive = false;


    // Logs into the /GARMIN/APPS/LOGS/appname.TXT
    // The file has to be created manually first. It is not possible to gather debug logs in production (after distribution in the ConnectIQ store)
    function log(a) {
        if (debug == true) {
            logtimestamp = Time.now().value();
            Sys.println(logtimestamp + ": " + a);
        }
    }

    function betalog(a) {
        if (beta == true) {
            logtimestamp = Time.now().value();
            Sys.println(logtimestamp + ": " + a);
        }
    }

    // Puts message in the messageQueue, also attempts to do some memory checks so as not to overload the underlying watch's queue
    function enqueue(message) {
        var freeMemRatio = Sys.getSystemStats().freeMemory*100/Sys.getSystemStats().totalMemory;
        log("free: " + Sys.getSystemStats().freeMemory);

        if (messageQueue.size() > 50) {
            log("MsgQ > 50!!!");
        }

        if (((freeMemRatio <= 7) && (messageQueue.size() > 0)) || (messageQueue.size() > 50)) {
            log("Removing" + messageQueue[0] + "from q, freeMemRatio:" + freeMemRatio + ",q size:" + messageQueue.size());
            messageQueue.remove(messageQueue[0]);
        }


        if (messageQueue.indexOf(message) == -1) {
            messageQueue.add(message);
            //log("Adding to q:" + message + " outQ: " + messageQueue);
        }
    }

    // Convenience global functions to enqueue specific messages to be sent to phone
    function sendResumeTracking() {
        enqueue("RESUME");
    }

    function sendPauseTracking() {
        enqueue("PAUSE");
    }

    function sendStopTracking() {
        enqueue("STOPPING");
    }

    function sendDismissAlarm() {
        enqueue("DISMISS");
    }

    function sendSnoozeAlarm() {
        enqueue("SNOOZE");
    }

    function sendConfirmConnection() {
        enqueue("CONFIRMCHECK");
    }


class SleepApp extends App.AppBase {

    const SAMPLE_PERIOD = 100; //ms
    const AGG_PERIOD = 10000; //ms
    var MAX_AGG_COUNT = 9;

    var phoneCommMethod;

    var info;
    var hrInfo;
    var listener;

    var scheduled_alarm_ts = 0;
    var delay = 0; // For delayed alarm vibration

    // Heart rates
    const HR_ON_COUNT = 120;//120;
    const HR_MAX_COUNT = 360;//360;
    var hrCurrentlyReading = false;
    var hrTracking = false;
    var hrValue = 0;
    var hrCount = 0;

    var timerCount = 0;
    var stopAppDelay = 0;

    // Alarms
    var alarm_gap_duration = 300; // Time between alarm pulses
    var alarm_gap_duration_current = alarm_gap_duration;
    var alarmCount = alarm_gap_duration;
    // Vibration patterns
    var vibrateOnAlarm = true;
    const shortPulse = [new Attention.VibeProfile(50, 200)];

    // Actigraphy
    var mX = [0];
    var mY = [0];
    var mZ = [0];
    var last = false;
    var lastValues = new [3];
    var max_sum = 0;
    var currentMax;
    var aggCount = 0;
    var batchSize = 12;
    var batch = [];
    // New actigraphy
    var batch_new = [];
    var max_sum_new = 0;

    function initialize() {
        AppBase.initialize();

        phoneCommMethod = method(:onMsg);
        if(Comm has :registerForPhoneAppMessages) {
            Comm.registerForPhoneAppMessages(phoneCommMethod);
        } else {
            notice = notice + "Err: Old CIQ version\n";
        }
    }

    function onMsg(msg) {
        handleIncomingMessage(msg.data.toString());
    }

//    //! onStart() is called on application start up
//    function onStart(state) {
//        log("--onStart--");
//        dataTimer = new Timer.Timer();
//        dataTimer.start( method(:timerCallback), SAMPLE_PERIOD, true);
//        sendStartingTracking();
//        now = Sys.getClockTime();
//        timecurrent = now.hour + ":" + now.min.format("%02d");
//        // current_heartrate = (Sensor.getInfo()).heartRate;
//        Ui.requestUpdate();
//
//        // Just for emulator
//        if (fakeTransmit == true) { notice = notice + "fakeTransmit";}
//    }

    // Start pitch counter
    function onStart(state) {
        sendStartingTracking();
        now = Sys.getClockTime();
        timecurrent = now.hour + ":" + now.min.format("%02d");
        Ui.requestUpdate();
        // initialize accelerometer
        var options = {:period => 1, :sampleRate => 3, :enableAccelerometer => true};
        try {
            Sensor.registerSensorDataListener(method(:timerCallback), options);
        }
        catch(e) {
            System.println(e.getErrorMessage());
        }
    }

    // Stop pitch counter
    function onStop(state) {
        Sensor.unregisterSensorDataListener();
        phoneCommMethod = null;
		log("onStop");
    }


    function onHr(sensor_info) { // measurement á 5 s
        // log("onHr: " + sensor_info.heartRate.toString());
        if (sensor_info.heartRate != null ) {
            current_heartrate = sensor_info.heartRate;
            sendHRData(current_heartrate);
        }

        //     hrCount = hrCount + 1;
        //     log("hrcount + 1");

        //     if (hrCurrentlyReading == true) {
        //         hrValue = hrValue + sensor_info.heartRate;
        //         log("HR read, hrValue: " + hrValue);
        //     }

        //     if ( (hrCount >= HR_ON_COUNT) && (hrCurrentlyReading == true) ) {
        //             log("switching off HR read");
        //             hrCurrentlyReading = false;
        //             sendHRData(hrValue/hrCount);
        //             hrValue = 0;
        //             log("sending HR data: " + hrValue);
        //     }

        //     if ( hrCount >= HR_MAX_COUNT ) {
        //         log("hrloop restart");
        //         hrCount = 0;
        //         hrCurrentlyReading = true;
        //     }
        // }
    }

    // Main timer loop - here we gather data from sensors, check for alarms and ring them, and send messages to phone
    function timerCallback(sensorData) {
    	//log("timer callback");
        mX = sensorData.accelerometerData.x;
        mY = sensorData.accelerometerData.y;
        mZ = sensorData.accelerometerData.z; 
        
        now = Sys.getClockTime();
        timecurrent = now.hour + ":" + now.min.format("%02d");
        if (timerCount % 60 == 0) {
            Ui.requestUpdate();
        }

        if (stopAppDelay < 5) {
            stopAppDelay++;
        }
//        if (timerCount % 10 == 0) {
//            // log("timerCallback");
//            gatherHR(info);
//            timerCount = 0;
//        }

        gatherData();

        if (alarm_currently_active) {
            alarmCount++;
            if (delay <= 0) {
                if (alarmViewActive != true) {
                    Ui.switchToView(new SleepAlarmView(), new SleepAlarmDelegate(), Ui.SLIDE_IMMEDIATE);
                }
                if (alarmCount >= alarm_gap_duration_current) {
                    ringAlarm();
                    alarm_gap_duration = Math.floor(alarm_gap_duration/2);
                    if (alarm_gap_duration < 10) {
                        alarm_gap_duration = 10;
                    }
                    alarm_gap_duration_current = alarm_gap_duration;
                    alarmCount = 0;
                }
            } else {
                delay = delay - SAMPLE_PERIOD;
            }
        } else {
            checkIfAlarmScheduledForNow();
        }
        
        timerCount++;
        sendNextMessage();
    }

    // MESSAGES TO PHONE
    // These messages are not needed globally
    function sendStartingTracking() {
        enqueue("STARTING");
    }
    function sendCurrentDataAndResetBatch() {
    	//log("SendCurrentDataAndResetBatch called");
        var toSend = ["DATA", batch.toString()];
        var toSend_new = ["DATA_NEW", batch_new.toString()];
        //log("transmitting: " + batch.toString());
        if (batch.size() > 0) {
            enqueue(toSend);
            enqueue(toSend_new);
            //batch = null;
            //batch_new = null;
            batch = [];
            batch_new = [];
        }
    }
    function sendHRData(hrAvg) {
        var HRtoSend = ["HR", hrAvg];
        enqueue(HRtoSend);
    }

    // Handling messages coming from the phone
    function handleIncomingMessage(mail) {
        var data;
        log("Incoming mail: " + mail);
        // betalog("Incoming mail: " + mail);

        if ( mail.equals("StopApp") && stopAppDelay == 5) {
            // Comm.emptyMailbox();
            Sys.exit();
        } else if ( mail.equals("Check") ) {
            sendConfirmConnection();
        } else if ( mail.find("Pause;") == 0 ) {
            // Currently doing nothing when pause received from phone
            data = extractDataFromIncomingMessage(mail).toNumber();  // time
            // enqueue(data);
            // TODO extract value and pause tracking (start sending -0.01s) and show pause time
        } else if ( mail.find("BatchSize;") == 0 ) {
            data = extractDataFromIncomingMessage(mail).toNumber(); // size
            setBatchSize(data);
        } else if ( mail.find("SetAlarm;") == 0 ) {
            data = extractDataFromIncomingMessage(mail).toNumber(); // timestamp
            setAlarm(data);
        } else if ( mail.find("StartAlarm;") == 0 ) {
            delay = extractDataFromIncomingMessage(mail).toNumber(); // delay
            if (delay == "-1") {
                vibrateOnAlarm = false;
                } else {
                    vibrateOnAlarm = true;
                }
            startAlarm();
        } else if ( mail.find("Hint;") == 0 ) {
            data = extractDataFromIncomingMessage(mail).toNumber();  // repeat
            doHint(data);
        } else if ( mail.find("StopAlarm;") == 0 ) {
            stopAlarm();
        } else if ( mail.equals("StartHRTracking")) {
            // Sensor.enableSensorEvents( method(:onHr) );
            // Sensor.setEnabledSensors( [Sensor.SENSOR_HEARTRATE] );
            // hrTracking = true;
            // hrCurrentlyReading = true;

        } else if ( mail.equals("StartTracking")) {

        } else {
            // mail = "Message not handled: " + mail;
            log("Message not handled" + mail.toString());
        }
    }

    function extractDataFromIncomingMessage(mail) {
        return mail.substring((mail.find(";"))+1,mail.length());
    }

    function gatherData() {
            store_max(); // saves to both max_sum and max_sum_new
	
			//log("left store_max max_sum:"+max_sum+" "+max_sum_new);
            if ( aggCount >= MAX_AGG_COUNT ) {
                batch.add(max_sum);
                batch_new.add(max_sum_new);
                max_sum_new = 0;
                max_sum = 0;
                aggCount = 0;
            }
            if ( batch.size() >= batchSize ) {
                sendCurrentDataAndResetBatch();
            }
            aggCount++;
            //log("current batchsize:"+batch.size()+" limit:"+batchSize);
            //log("current agg counter:"+aggCount);

    }

    function gatherHR(hrInfo) {
        if (hrTracking == true) {
        // log("has nonnull heartrate: " + hrInfo.heartRate);
            if ( hrInfo has :heartRate && hrInfo.heartRate != null ) {

                hrCount = hrCount + 1;
                // log(hrCount);
                if (beta == true) {
	                current_heartrate = hrInfo.heartRate;
	            }

                if (hrCurrentlyReading == true) {
                    // log("hrinfo, heartrate" + hrInfo + " " +hrInfo.heartRate);
    	            hrValue = hrValue + hrInfo.heartRate;
                }

                if ( (hrCount >= HR_ON_COUNT) && (hrCurrentlyReading == true) ) {
 					// log("hrinfo, heartrate" + hrInfo + " " +hrInfo.heartRate);
    	            // log("switching off HR read");
                    hrCurrentlyReading = false;
                    // Sensor.setEnabledSensors([]); // disables heart rate sensor
                    sendHRData(hrValue/hrCount);
                    hrValue = 0;
                }

                if ( hrCount >= HR_MAX_COUNT) {
                    // log("hrloop restart");
                    hrCount = 0;
                    hrCurrentlyReading = true;
                }
            }
        }
    }

    // Batch can be any number but usually we set it either to 1 when the phone user is currently viewing the phone so he has data from watch sent to phone immediately for viewing, or to 12 when the phone is idle, to conserve battery (we don't have to send via bluetooth as often)
    function setBatchSize(newBatchSize) {
        //log("Batch set to " + newBatchSize.toString());
        batchSize = newBatchSize;
        sendCurrentDataAndResetBatch();
    }

    function checkIfAlarmScheduledForNow() {
        if (now == scheduled_alarm_ts) {
            StartAlarm();
        }
    }

    function setAlarm(timestamp) {
        log("Alarm set to " + timestamp.toString());
        scheduled_alarm_ts = timestamp;
    }

    function startAlarm() {
        alarm_currently_active = true;
        alarm_gap_duration = 300;
        alarm_gap_duration_current = 300;
        alarmCount = alarm_gap_duration;
    }

    function ringAlarm() {
        if ( vibrateOnAlarm == true ) {
            if (Attention has :vibrate ) {
                Attention.vibrate(shortPulse);
            } else {
                if (Attention has :playTone) {
                    Attention.playTone(8); // TONE_ALARM
                }
            }
        }
    }

    // Hint is lucid dreaming or anti-snoring vibration
    function doHint(repeat) {
        log("Hint requested " + repeat.toString() + " times.");
        // Garmin only supports vibrating up to 8 VibeProfiles, so we have to cap repeating on 4
        if (repeat > 4) {
            repeat = 4;
        }
        log("Doing HINT " + repeat.toString() + " times.");

        if (Attention has :vibrate) {
            var vibrateData = [];
            for ( var i = 0; i < repeat; i += 1) {
                vibrateData.add(new Attention.VibeProfile(  50, 1000));
                vibrateData.add(new Attention.VibeProfile(  0, 1000));
            }
            Attention.vibrate(vibrateData);
        } else if (Attention has :playTone) {
            for ( var i = 0; i < repeat; i += 1) {
                Attention.playTone(0); // playing TONE_KEY
            }
        }
    }

    function stopAlarm() {
        alarm_currently_active = false;
        Ui.switchToView(new SleepView(), new SleepDelegate(), Ui.SLIDE_IMMEDIATE);
        alarmViewActive = false;
    }

    function sendNextMessage() {
    	//log("SendNextMessage");
    	//log("Size:"+ messageQueue.size() + deliveryInProgress + Sys.getDeviceSettings().phoneConnected);
        if (deliveryErrorCount > MAX_DELIVERY_ERROR) {
        	//log("Too many errors");
            deliveryPauseCount++;
            if (deliveryPauseCount > MAX_DELIVERY_PAUSE) {
                deliveryPauseCount = 0;
                deliveryErrorCount = 0;
            }
        //} else if (messageQueue.size() > 0 && !deliveryInProgress && Sys.getDeviceSettings().phoneConnected) {
        } else if (messageQueue.size() > 0 && !deliveryInProgress ) {
                var message = messageQueue[0];
                deliveryInProgress = true;
                if (fakeTransmit == true) {
                	log("FakeTransmit: " + message);
                	new SleepListener(message).onComplete();
                } else {
                	//log("Actually Sending now");
	                Comm.transmit(message, null, new SleepListener(message));
                }
        }
    }

    function store_max() {
		//log("store_max called");
		var size = mX.size();
		//log("size: "+size);
		for ( var i = 0; i < size; i += 1) {
		log("for loop i:"+i);
        if (last) {
        	//log("x" + currentValues[0] + "y" + currentValues[1] + "z" + currentValues[2]);
            var sum = ((lastValues[0] - mX[i]).abs() + (lastValues[1] - mY[i]).abs() + (lastValues[2] - mZ[i]).abs());
            var sum_new = Math.floor(Math.sqrt((mX[i] * mX[i]) + (mY[i] * mY[i]) + (mZ[i] * mZ[i]))).toNumber();

            if (sum > max_sum) {
                max_sum = sum;
            }
            if (sum_new > max_sum_new) {
                max_sum_new = sum_new;
            }

        }

        last = true;
        lastValues[0] = mX[0];
        lastValues[1] = mY[0];
        lastValues[2] = mZ[0];
        }
    }

//    //! onStop() is called when your application is exiting
//    function onStop(state) {
//    	phoneCommMethod = null;
//		log("onStop");
//        // messageQueue = null;
//        betalog("usedMem" + Sys.getSystemStats().usedMemory + "freeMem" + Sys.getSystemStats().freeMemory + "totalMem" + Sys.getSystemStats().totalMemory);
//		// messageQueue = null;
//    }

    //! Return the initial view of your application here
    function getInitialView() {
        return [ new SleepView(), new SleepDelegate() ];
    }
}