package com.urbandroid.sleep.garmin;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import com.garmin.android.connectiq.ConnectIQ;
import com.garmin.android.connectiq.IQApp;
import com.garmin.android.connectiq.IQDevice;
import com.garmin.android.connectiq.exception.InvalidStateException;
import com.garmin.android.connectiq.exception.ServiceUnavailableException;
import com.urbandroid.sleep.garmin.logging.Logger;

import java.util.List;

import static com.garmin.android.connectiq.IQApp.IQAppStatus.INSTALLED;

public class MainActivity extends Activity {

    private boolean debug = true;
    private static final String TAG = MainActivity.class.getSimpleName();

    private static final String PACKAGE_SLEEP = "com.urbandroid.sleep";
    private static final String PACKAGE_GCM = "com.garmin.android.apps.connectmobile";
    private static final String IQ_APP_ID = SleepAsAndroidProviderService.IQ_APP_ID;
    private boolean sleepInstalled = true;
    private boolean gcmInstalled = true;
    private boolean watchappInstalled = true;

    private ConnectIQ mConnectIQ;
    private IQDevice mDevice;

    private ConnectIQ.IQDeviceEventListener mDeviceEventListener = new ConnectIQ.IQDeviceEventListener() {
        @Override
        public void onDeviceStatusChanged(IQDevice device, IQDevice.IQDeviceStatus status) {
        }
    };

    private ConnectIQ.ConnectIQListener mListener = new ConnectIQ.ConnectIQListener() {

        @Override
        public void onInitializeError(ConnectIQ.IQSdkErrorStatus errStatus) {
        }

        @Override
        public void onSdkReady() {

            registerDevice();

//            try {
//                mConnectIQ.getApplicationInfo(IQ_APP_ID, mDevice, new ConnectIQ.IQApplicationInfoListener() {
//                    @Override
//                    public void onApplicationInfoReceived( IQApp app ) {
//                        if (app != null) {
//                            if (app.getStatus() == INSTALLED) {
//                                watchappInstalled = true;
//    //                            if (app.getVersion() < MY_CURRENT_VERSION) {
//    //                                 Prompt the user to upgrade
//    //                            }
//                            } else if (app.getStatus() == IQApp.IQAppStatus.NOT_INSTALLED) {
//                            } else {
//                                Logger.logDebug(TAG + ": Error getting watch app: " + app.getStatus());
//                            }
//                        }
//                        Logger.logDebug(TAG + "Watchapp installed: " + watchappInstalled);
//                        findViewById(R.id.card_install_watchapp).setVisibility(!watchappInstalled ? View.VISIBLE : View.GONE);
//                    }
//                    @Override
//                    public void onApplicationNotInstalled( String applicationId ) {
//                    }
//                });
//            } catch (InvalidStateException e) {
//                Logger.logSevere(e);
//            } catch (ServiceUnavailableException e) {
//                Logger.logSevere(e);
//            }

        }

        @Override
        public void onSdkShutDown() {
            try {
                if (mConnectIQ != null) {
                    mConnectIQ.unregisterForDeviceEvents(mDevice);
                }
            } catch (InvalidStateException e) {
                Logger.logSevere(e);
            } catch (IllegalArgumentException e) {
                Logger.logSevere(e);
            } catch (RuntimeException e) {
                Logger.logSevere(e);
            }
        }
    };

    public void registerDevice() {
        try {
            List<IQDevice> devices = mConnectIQ.getKnownDevices();

            if (devices != null && devices.size() > 0) {
//              Take just the first device we find
                mDevice = devices.get(0);
                mConnectIQ.registerForDeviceEvents(mDevice, mDeviceEventListener);
                Logger.logInfo("registered: " + mDevice.toString());
            } else {
                return;
            }
        } catch (InvalidStateException e) {
            Logger.logSevere(e);
        } catch (ServiceUnavailableException e) {
            Logger.logSevere(e);
        }

        try {
            mConnectIQ.registerForDeviceEvents(mDevice, new ConnectIQ.IQDeviceEventListener() {

                @Override
                public void onDeviceStatusChanged(IQDevice device, IQDevice.IQDeviceStatus status) {
                    Logger.logInfo("Device " + device.getDeviceIdentifier() + "  " + status);
                }
            });
        } catch (InvalidStateException e) {
            Logger.logSevere(e);
        }
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        try {
            mConnectIQ.shutdown(this);
        } catch (InvalidStateException e) {
            Logger.logSevere(e);
        } catch (IllegalArgumentException e) {
            Logger.logSevere(e);
        } catch (RuntimeException e) {
            Logger.logSevere(e);
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        GlobalInitializer.initializeIfRequired(this);
        setContentView(R.layout.activity_main);

        try {
            this.getPackageManager().getApplicationInfo(PACKAGE_SLEEP, 0);
        } catch (PackageManager.NameNotFoundException e) {
            sleepInstalled = false;
        }

        try {
            this.getPackageManager().getApplicationInfo(PACKAGE_GCM, 0);
        } catch (PackageManager.NameNotFoundException e) {
            gcmInstalled = false;
        }

        mConnectIQ = ConnectIQ.getInstance(this, ConnectIQ.IQConnectType.WIRELESS);
        //mConnectIQ =  ConnectIQ.getInstance(this, ConnectIQ.IQConnectType.TETHERED);
        mConnectIQ.initialize(this, true, mListener);

        findViewById(R.id.install_gcm).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                installGCM();
            }
        });

        findViewById(R.id.install_saa).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                installSleep();
            }
        });

        findViewById(R.id.install_watchapp).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                installWatchApp(mConnectIQ);
            }
        });

        findViewById(R.id.setup).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                setupSleep();
            }
        });

        findViewById(R.id.card_install_saa).setVisibility(!sleepInstalled ? View.VISIBLE : View.GONE);
        findViewById(R.id.card_install_gcm).setVisibility(!gcmInstalled ? View.VISIBLE : View.GONE);
    }

    private void setupSleep() {
            try {
                Intent i = new Intent();
                i.setClassName(PACKAGE_SLEEP, PACKAGE_SLEEP+".alarmclock.settings.SmartwatchSettingsActivity");
                startActivity(i);
            } catch (Exception e) {
                try {
                    Intent i = new Intent();
                    i.setClassName(PACKAGE_SLEEP, PACKAGE_SLEEP+".alarmclock.AlarmClock");
                    startActivity(i);
                } catch (Exception ee) {
                    Logger.logSevere(ee);
                    finish();
                }
            }
        }

    private void installSleep() {
        try {
            Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id="+PACKAGE_SLEEP));
            startActivity(i);
        } catch (Exception e) {
            Logger.logSevere(e);
        }
    }

    private void installGCM() {
        try {
            Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id="+PACKAGE_GCM));
            startActivity(i);
        } catch (Exception e) {
            Logger.logSevere(e);
        }
    }

    private void installWatchApp(final ConnectIQ mConnectIQ) {
        try {
            mConnectIQ.openStore(new IQApp(IQ_APP_ID).getApplicationId());
        } catch (InvalidStateException ee) {
            mConnectIQ.initialize(this, true, new ConnectIQ.ConnectIQListener() {
                @Override
                public void onSdkReady() {
                    try {
                        mConnectIQ.openStore(new IQApp(IQ_APP_ID).getApplicationId());
                    } catch (Exception e) {
                        Logger.logSevere(e);
                    }
                }

                @Override
                public void onInitializeError(ConnectIQ.IQSdkErrorStatus iqSdkErrorStatus) {

                }

                @Override
                public void onSdkShutDown() {

                }
            });

        } catch (Exception e) {
            Logger.logSevere(e);
        }
    }
}
