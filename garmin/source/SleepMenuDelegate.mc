using Toybox.WatchUi as Ui;
using Toybox.System as Sys;
using Toybox.Communications as Comm;

class SleepMenuDelegate extends Ui.MenuInputDelegate {

    function initialize() {
        MenuInputDelegate.initialize();
    }

    function onMenuItem(item) {
        if (item == :item_1) {
	        sendPauseTracking();
        } else if (item == :item_2) {
            sendResumeTracking();
        } else if (item == :item_3) {
            // dataTimer.stop();
            // secondTimer.stop();
            if (Sys.getDeviceSettings().phoneConnected && !fakeTransmit) {
                Comm.transmit("STOPPING", null, new SleepNowListener("STOPPING"));
            }
            // if (exitTapped == true) {
            //     log("exiting via menu");
            //     Sys.exit();
            // }
            exitTapped = true;
        } else if (item == :item_4) {
            log("Force stopped via menu");
            if (Sys.getDeviceSettings().phoneConnected && !fakeTransmit) {
            	Comm.transmit("STOPPING", null, new SleepNowListener("STOPPING"));
            }
            Sys.exit();
        }
    }
}