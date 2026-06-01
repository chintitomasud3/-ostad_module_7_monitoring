const express = require('express');
const mongoose = require('mongoose');
const path = require('path');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;

// ✅ CORS Configuration - Allow ANY Origin with Credentials Support
app.use(cors({
  origin: (origin, callback) => {
    // Allow all origins dynamically
    callback(null, true);
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With']
}));

// 📦 Middleware
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// 🔗 MongoDB Connection
const MONGO_URI = 'mongodb://127.0.0.1:27017/express_names_db';
mongoose.connect(MONGO_URI)
  .then(() => console.log('✅ MongoDB connected successfully'))
  .catch(err => console.error('❌ MongoDB connection error:', err));

// 📋 Mongoose Schema & Model
const nameSchema = new mongoose.Schema({
  name: { type: String, required: true }
}, { timestamps: true });

const Name = mongoose.model('Name', nameSchema);

// 📥 API Routes

// ✅ Fetch all names
app.get('/api/names', async (req, res) => {
  try {
    const names = await Name.find().sort({ createdAt: -1 });
    res.json(names);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ✅ Add a new name
app.post('/api/names', async (req, res) => {
  try {
    const newName = new Name({ name: req.body.name });
    await newName.save();
    res.status(201).json(newName);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// ✅ Update a name
app.put('/api/names/:id', async (req, res) => {
  try {
    const updatedName = await Name.findByIdAndUpdate(
      req.params.id,
      { name: req.body.name },
      { new: true }
    );
    res.json(updatedName);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// ✅ Delete a name
app.delete('/api/names/:id', async (req, res) => {
  try {
    await Name.findByIdAndDelete(req.params.id);
    res.json({ message: 'Successfully deleted' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});



// 🚀 Start Server
app.listen(PORT, () => {
  console.log(`🚀 Server running: http://localhost:${PORT}`);
});
