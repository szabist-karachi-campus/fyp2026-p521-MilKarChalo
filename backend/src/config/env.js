import dotenv from 'dotenv';
dotenv.config();

export const env = {
  port: process.env.PORT || 4000,
  nodeEnv: process.env.NODE_ENV || 'development',
  clientOrigin: process.env.CLIENT_ORIGIN || 'http://localhost:3000',

  db: {
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    port: process.env.DB_PORT || 3306,
  },

  jwt: {
    secret: process.env.JWT_SECRET,
  },

  smtp: {
    host: process.env.SMTP_HOST,
    port: Number(process.env.SMTP_PORT || 587),
    secure: process.env.SMTP_SECURE === 'true',
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },

  otp: {
    length: Number(process.env.OTP_LENGTH || 6),
    ttlSeconds: Number(process.env.OTP_TTL_SECONDS || 600),
    resendCooldown: Number(process.env.OTP_RESEND_COOLDOWN || 120),
  },

  firebase: {
    serviceAccountPath: process.env.FIREBASE_SERVICE_ACCOUNT_PATH || null,
  },

  textbee: {
    apiKey: process.env.TEXTBEE_API_KEY || '',
    deviceId: process.env.TEXTBEE_DEVICE_ID || '',
  },

  googleMaps: {
    apiKey: process.env.GOOGLE_MAPS_API_KEY || '',
  },
};
