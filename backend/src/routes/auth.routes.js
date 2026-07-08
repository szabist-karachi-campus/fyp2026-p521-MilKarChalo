import { Router } from 'express';
import {
  register, verifyEmailOtp, resendSignupOtp,
  login, verifyLoginOtp, resendLoginOtp,
  forgotPassword, verifyResetOtp, resetPassword, adminLogin,
} from '../controllers/auth.controller.js';

import { vSignup, vLogin, vSendOtp, vVerifyOtpEmailCode } from '../utils/validators.js';

const r = Router();

// Signup
r.post('/register', vSignup, register);
r.post('/verify-otp', vVerifyOtpEmailCode, verifyEmailOtp);       
r.post('/resend-otp', vSendOtp, resendSignupOtp);                 

// Login
r.post('/admin-login', vLogin, adminLogin);
r.post('/login', vLogin, login);
r.post('/verify-login-otp', vVerifyOtpEmailCode, verifyLoginOtp);  
r.post('/resend-login-otp', vSendOtp, resendLoginOtp);            

// Password reset
r.post('/forgot', vSendOtp, forgotPassword);                       
r.post('/verify-reset', vVerifyOtpEmailCode, verifyResetOtp);      
r.post('/reset', vVerifyOtpEmailCode, resetPassword);          

export default r;