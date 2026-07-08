import { createRequire } from 'module';
import { readFileSync } from 'fs';
import { env } from './env.js';

// firebase-admin v12+ uses named exports rather than a default namespace object.
// Use createRequire so the CJS package loads correctly inside an ESM project.
const require = createRequire(import.meta.url);
const {
  initializeApp,
  getApps,
  cert,
} = require('firebase-admin/app');
const { getMessaging } = require('firebase-admin/messaging');

let messaging = null;

const serviceAccountPath = env.firebase.serviceAccountPath;

if (!serviceAccountPath) {
  console.warn(
    '[Firebase] FIREBASE_SERVICE_ACCOUNT_PATH is not set. ' +
    'Push notifications will be disabled.'
  );
} else {
  try {
    const serviceAccount = JSON.parse(readFileSync(serviceAccountPath, 'utf8'));

    // Guard against double-initialisation (e.g. hot-reload in dev)
    if (getApps().length === 0) {
      initializeApp({
        credential: cert(serviceAccount),
      });
    }

    messaging = getMessaging();
  } catch (err) {
    console.warn(
      `[Firebase] Failed to initialise Firebase Admin SDK: ${err.message}. ` +
      'Push notifications will be disabled.'
    );
  }
}

export { messaging };
