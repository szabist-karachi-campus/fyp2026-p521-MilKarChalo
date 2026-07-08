import nodemailer from 'nodemailer';
import { env } from './env.js';

export const transporter = nodemailer.createTransport({
  host: env.smtp.host,
  port: env.smtp.port,
  secure: env.smtp.secure,
  auth: { user: env.smtp.user, pass: env.smtp.pass }
});
export async function sendOtpMail({ to, code, purpose }) {
  const subject = `Your ${purpose} OTP code`;
  const html = `<p>Your ${purpose} OTP is:</p>
                <h2>${code}</h2>
                <p>It expires in 10 minutes.</p>`;
  await transporter.sendMail({ from: process.env.SMTP_USER, to, subject, html });
}