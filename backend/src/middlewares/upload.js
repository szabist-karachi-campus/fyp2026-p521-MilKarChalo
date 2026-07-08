import multer from 'multer';
import path from 'path';
import fs from 'fs';

// 1. Ensure the upload directory exists
const uploadDir = 'uploads';
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir);
}

// 2. Configure Storage
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, uploadDir); // Save files to 'uploads/' folder
  },
  filename: function (req, file, cb) {
    // Generate unique name: userId-timestamp.ext
    // We use req.user.uid if available, otherwise 'unknown'
    const userId = req.user ? req.user.uid : 'temp'; 
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    const ext = path.extname(file.originalname);
    cb(null, `${userId}-${uniqueSuffix}${ext}`);
  }
});

// 3. Filter (Optional: Only accept images)

const fileFilter = (req, file, cb) => {
  // 1. Check by mimetype
  const isImageMime = file.mimetype.startsWith('image/');
  
  // 2. Check by file extension (backup)
  const filetypes = /jpeg|jpg|png|webp/;
  const extname = filetypes.test(path.extname(file.originalname).toLowerCase());

  if (isImageMime || extname) {
    return cb(null, true);
  } else {
    // This error matches what you saw in your console
    cb(new Error('Only image files are allowed!'), false);
  }
};

export const upload = multer({ 
  storage: storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // Limit to 5MB
  fileFilter: fileFilter
});
