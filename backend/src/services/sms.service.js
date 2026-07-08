import { env } from '../config/env.js';

const TEXTBEE_URL = `https://api.textbee.dev/api/v1/gateway/devices/${env.textbee.deviceId}/send-sms`;

/**
 * Send an SMS to a single recipient via TextBee.
 * @param {string} phone   - E.164 or local number format
 * @param {string} message - SMS body text
 * @returns {Promise<boolean>} true if sent, false on failure
 */
export async function sendSms(phone, message) {
  if (!env.textbee.apiKey || !env.textbee.deviceId) {
    console.warn('[SMS] TextBee credentials not configured — skipping SMS.');
    return false;
  }

  try {
    const res = await fetch(TEXTBEE_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': env.textbee.apiKey,
      },
      body: JSON.stringify({
        recipients: [phone],
        message,
      }),
    });

    if (!res.ok) {
      const body = await res.text();
      console.error(`[SMS] TextBee error ${res.status}: ${body}`);
      return false;
    }

    console.log(`[SMS] Sent to ${phone}`);
    return true;
  } catch (e) {
    console.error(`[SMS] Failed to send to ${phone}:`, e.message);
    return false;
  }
}

/**
 * Send the same message to multiple recipients.
 * Failures on individual numbers do not abort the others.
 * @param {string[]} phones
 * @param {string}   message
 * @returns {Promise<{sent: number, failed: number}>}
 */
export async function sendSmsToMany(phones, message) {
  let sent = 0;
  let failed = 0;
  for (const phone of phones) {
    const ok = await sendSms(phone, message);
    ok ? sent++ : failed++;
  }
  return { sent, failed };
}
