import { body } from 'express-validator';

const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/i;
const nameAlpha = /^[A-Za-z\s]+$/;
const phonePk = /^(?:\+92\d{10}|03\d{9})$/;
const cnic13 = /^\d{13}$/;
const passwordStrong = /^(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&#])[A-Za-z\d@$!%*?&#]{6,}$/;

export const vSignup = [
  body('role')
    .isIn(['driver', 'passenger'])
    .withMessage('Role must be driver or passenger'),

  body('name')
    .trim()
    .matches(nameAlpha)
    .withMessage('Name should contain only alphabets')
    .isLength({ min: 2 })
    .withMessage('Name must be at least 2 characters long'),

  body('email')
    .trim()
    .toLowerCase()
    .matches(emailRegex)
    .withMessage('Invalid email format'),

  body('phone')
    .trim()
    .matches(phonePk)
    .withMessage('Phone must be +923XXXXXXXXX or 03XXXXXXXXX'),

  body('gender')
    .isIn(['male', 'female', 'other'])
    .withMessage('Invalid gender'),

  body('city')
    .trim()
    .isLength({ min: 2 })
    .withMessage('City must be at least 2 characters'),

  body('password')
    .matches(passwordStrong)
    .withMessage(
      'Password must have at least 6 characters, one uppercase letter, one number, and one special character'
    ),
];


export const vLogin = [
  body('email')
    .optional()
    .trim()
    .toLowerCase()
    .matches(emailRegex)
    .withMessage('Invalid email format'),

  body('phone')
    .optional()
    .trim()
    .matches(phonePk)
    .withMessage('Phone must be +923XXXXXXXXX or 03XXXXXXXXX'),

  body('password')
    .isString()
    .matches(passwordStrong)
    .withMessage(
      'Password must have at least 6 characters, one uppercase letter, one number, and one special character'
    ),
];


export const vSendOtp = [
  body('email')
    .trim()
    .toLowerCase()
    .matches(emailRegex)
    .withMessage('Invalid email format'),
];


// NEW: Validator for verify endpoints that only need email + code (no purpose field)
export const vVerifyOtpEmailCode = [
  body('email')
    .trim()
    .toLowerCase()
    .matches(emailRegex)
    .withMessage('Invalid email format'),

  body('code')
    .isLength({ min: 6, max: 6 })
    .isNumeric()
    .withMessage('OTP code must be 6 digits'),
];

export const vVerifyOtp = [
  body('purpose')
    .optional()  // Made optional since endpoints now determine purpose
    .isIn(['signup', 'reset', 'login'])
    .withMessage('Purpose must be signup, reset, or login'),

  body('email')
    .trim()
    .toLowerCase()
    .matches(emailRegex)
    .withMessage('Invalid email format'),

  body('code')
    .isLength({ min: 6, max: 6 })
    .isNumeric()
    .withMessage('OTP code must be 6 digits'),
];


export const vDriverProfile = [
  body('cnic')
    .matches(cnic13)
    .withMessage('CNIC must be 13 digits'),

  body('driving_license_no')
    .trim()
    .isLength({ min: 3 })
    .withMessage('Driving license number must be at least 3 characters'),

  body('address')
    .trim()
    .isLength({ min: 5 })
    .withMessage('Address must be at least 5 characters'),

  body('emergency_contact_name')
    .trim()
    .matches(nameAlpha)
    .withMessage('Emergency contact name should contain only alphabets')
    .isLength({ min: 10 }),

  body('emergency_contact_phone')
    .trim()
    .matches(phonePk)
    .withMessage('Emergency contact phone must be valid Pakistani number'),
];


export const vPassengerProfile = [
  body('address')
    .trim()
    .isLength({ min: 5 })
    .withMessage('Address must be at least 5 characters'),

  body('emergency_contact_name')
    .trim()
    .matches(nameAlpha)
    .withMessage('Emergency contact name should contain only alphabets')
    .isLength({ min: 2 }),

  body('emergency_contact_phone')
    .trim()
    .matches(phonePk)
    .withMessage('Emergency contact phone must be valid Pakistani number'),

  body('gender_preference')
    .isIn(['male', 'female', 'both'])
    .withMessage('Gender preference must be male, female, or both'),
];

export const vVehicle = [
  body('make').isString().trim().notEmpty().withMessage('Make is required'),
  body('model').isString().trim().notEmpty().withMessage('Model is required'),
  body('color').isString().trim().notEmpty().withMessage('Color is required'),
  body('plate_no').isString().trim().notEmpty().withMessage('Plate number is required'),
  // FIX: multipart/form-data sends ALL fields as strings (e.g. "4").
  // toInt() converts it to a number first, then isInt() validates it correctly.
  body('seats')
    .toInt()
    .isInt({ min: 1, max: 16 })
    .withMessage('Seats must be a number between 1 and 16'),
];