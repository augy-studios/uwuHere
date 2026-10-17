/*
 * Tapping phones: while the host page has it on (HerePlugin.tap), this phone answers as an NFC tag
 * to any phone that touches it, so the other phone needs no app, only its own tag reading, which
 * opens the link in its browser. Most Android phones read tags whenever they're unlocked, and
 * iPhones from the XS on.
 *
 * The tag holds one link, made fresh for each tap: the event's join page with a one-time token
 * on the end, signed with the event's host key (main-site/api/_lib/tap.js says what's in it and
 * how the server checks it). Making one needs no connection.
 *
 * Android calls this host card emulation. It routes the NFC Forum's NDEF tag application
 * (D2760000850101, res/xml/tap_service.xml) here, and this answers it the way an NFC Forum Type 4
 * tag does: select the application, read its capability container (file E103), then read the
 * NDEF file (E104), which is the link's length and the link.
 *
 * Off, the service is disabled outright, so this phone doesn't claim the tag application when
 * nobody is hosting, and another app on it that answers as a tag keeps working.
 */
package org.uwuapps.here;

import android.content.ComponentName;
import android.content.Context;
import android.content.pm.PackageManager;
import android.nfc.NdefMessage;
import android.nfc.NdefRecord;
import android.nfc.NfcAdapter;
import android.nfc.cardemulation.HostApduService;
import android.os.Bundle;
import android.util.Base64;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Arrays;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

public class TapService extends HostApduService {
    // Told about each tap, for the host page's "Phone tapped" (HerePlugin).
    interface Listener {
        void tapped();
    }

    // What to hand out, from HerePlugin.tap. Null while off.
    private static volatile String code;
    private static volatile byte[] hostKey;
    static volatile Listener listener;

    private static final SecureRandom RANDOM = new SecureRandom();

    private static final byte[] OK = {(byte) 0x90, 0x00};
    private static final byte[] NOT_FOUND = {0x6A, (byte) 0x82};
    private static final byte[] WRONG_OFFSET = {0x6B, 0x00};
    private static final byte[] UNSUPPORTED = {0x6D, 0x00};

    private static final byte INS_SELECT = (byte) 0xA4;
    private static final byte INS_READ_BINARY = (byte) 0xB0;

    // The capability container: version 2.0, reads of up to 59 bytes at a time, and one NDEF
    // file, E104, of at most 512 bytes, readable and never writable.
    private static final byte[] CAPABILITY_CONTAINER = {
            0x00, 0x0F,             // its own length
            0x20,                   // mapping version 2.0
            0x00, 0x3B,             // most bytes a read answers
            0x00, 0x34,             // most bytes a write sends
            0x04, 0x06,             // the NDEF file's details:
            (byte) 0xE1, 0x04,      //   its id
            0x02, 0x00,             //   its largest size
            0x00,                   //   anyone may read it
            (byte) 0xFF,            //   nobody may write it
    };

    // This tap's files: the link is made once, as the tag application is selected, so every read
    // in one tap sees the same one.
    private byte[] ndefFile;
    private byte[] selected;

    static boolean supported(Context context) {
        return NfcAdapter.getDefaultAdapter(context) != null
                && context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION);
    }

    static void start(Context context, String eventCode, String key) {
        code = eventCode;
        hostKey = key.getBytes(StandardCharsets.UTF_8);
        setEnabled(context, true);
    }

    static void stop(Context context) {
        code = null;
        hostKey = null;
        setEnabled(context, false);
    }

    static boolean active() {
        return code != null;
    }

    private static void setEnabled(Context context, boolean on) {
        ComponentName me = new ComponentName(context, TapService.class);
        int state = on ? PackageManager.COMPONENT_ENABLED_STATE_ENABLED : PackageManager.COMPONENT_ENABLED_STATE_DISABLED;
        PackageManager pm = context.getPackageManager();
        if (pm.getComponentEnabledSetting(me) != state) pm.setComponentEnabledSetting(me, state, PackageManager.DONT_KILL_APP);
    }

    @Override
    public byte[] processCommandApdu(byte[] apdu, Bundle extras) {
        if (apdu == null || apdu.length < 4) return UNSUPPORTED;
        byte ins = apdu[1];
        byte p1 = apdu[2];

        // The tag application, by name: Android only sends it here if it's ours.
        if (ins == INS_SELECT && p1 == 0x04) {
            String eventCode = code;
            byte[] key = hostKey;
            if (eventCode == null || key == null) return NOT_FOUND;
            try {
                ndefFile = ndefFile(link(eventCode, key));
            } catch (GeneralSecurityException e) {
                return NOT_FOUND;
            }
            selected = null;
            return OK;
        }

        // A file, by its id.
        if (ins == INS_SELECT && p1 == 0x00 && apdu.length >= 7 && apdu[4] == 0x02) {
            int id = ((apdu[5] & 0xFF) << 8) | (apdu[6] & 0xFF);
            if (id == 0xE103) {
                selected = CAPABILITY_CONTAINER;
            } else if (id == 0xE104 && ndefFile != null) {
                selected = ndefFile;
                Listener l = listener;
                if (l != null) l.tapped();
            } else {
                selected = null;
                return NOT_FOUND;
            }
            return OK;
        }

        if (ins == INS_READ_BINARY) {
            if (selected == null) return NOT_FOUND;
            int offset = ((apdu[2] & 0x7F) << 8) | (apdu[3] & 0xFF);
            int wanted = apdu.length > 4 ? apdu[4] & 0xFF : 0;
            if (wanted == 0) wanted = 256;
            if (offset > selected.length) return WRONG_OFFSET;
            int length = Math.min(wanted, selected.length - offset);
            byte[] out = new byte[length + 2];
            System.arraycopy(selected, offset, out, 0, length);
            out[length] = OK[0];
            out[length + 1] = OK[1];
            return out;
        }

        return UNSUPPORTED;
    }

    @Override
    public void onDeactivated(int reason) {
        ndefFile = null;
        selected = null;
    }

    // https://here.uwuapps.org/join?id=CODE&tap=TIME.NONCE.MAC, as main-site/api/_lib/tap.js reads it.
    static String link(String eventCode, byte[] key) throws GeneralSecurityException {
        long time = System.currentTimeMillis() / 1000;
        byte[] nonceBytes = new byte[9];
        RANDOM.nextBytes(nonceBytes);
        String nonce = base64url(nonceBytes);

        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(key, "HmacSHA256"));
        byte[] full = mac.doFinal(("uwuhere-tap:" + eventCode + ":" + time + ":" + nonce).getBytes(StandardCharsets.UTF_8));
        String sig = base64url(Arrays.copyOf(full, 16));

        return MainActivity.SITE + "/join?id=" + eventCode + "&tap=" + time + "." + nonce + "." + sig;
    }

    // The NDEF file: the message's length in two bytes, then the message, one URI record.
    private static byte[] ndefFile(String url) {
        byte[] message = new NdefMessage(NdefRecord.createUri(url)).toByteArray();
        byte[] file = new byte[message.length + 2];
        file[0] = (byte) (message.length >> 8);
        file[1] = (byte) message.length;
        System.arraycopy(message, 0, file, 2, message.length);
        return file;
    }

    private static String base64url(byte[] bytes) {
        return Base64.encodeToString(bytes, Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
    }
}
