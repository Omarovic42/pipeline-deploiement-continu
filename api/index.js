const express = require('express');
const cors = require('cors');
const morgan = require('morgan');

// Création de l'application Express
const app = express();
const port = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(morgan('combined'));

// Base de données simulée pour les capteurs
const sensors = [
  { id: 1, name: 'Temperature Sensor 1', type: 'temperature', location: 'Building A', value: 22.5, unit: '°C', timestamp: new Date() },
  { id: 2, name: 'Humidity Sensor 1', type: 'humidity', location: 'Building A', value: 45.0, unit: '%', timestamp: new Date() },
  { id: 3, name: 'CO2 Sensor 1', type: 'co2', location: 'Building B', value: 415, unit: 'ppm', timestamp: new Date() },
  { id: 4, name: 'Temperature Sensor 2', type: 'temperature', location: 'Building B', value: 24.2, unit: '°C', timestamp: new Date() },
  { id: 5, name: 'Light Sensor 1', type: 'light', location: 'Building C', value: 450, unit: 'lux', timestamp: new Date() },
];

// Routes
app.get('/', (req, res) => {
  res.json({
    message: 'API de supervision de capteurs environnementaux',
    version: '1.0.0',
    endpoints: [
      { method: 'GET', path: '/sensors', description: 'Liste tous les capteurs' },
      { method: 'GET', path: '/sensors/:id', description: 'Détails d\'un capteur spécifique' },
      { method: 'POST', path: '/sensors/:id/data', description: 'Envoie des données pour un capteur' },
      { method: 'GET', path: '/health', description: 'Vérifie l\'état de l\'API' }
    ]
  });
});

app.get('/sensors', (req, res) => {
  res.json(sensors);
});

app.get('/sensors/:id', (req, res) => {
  const id = parseInt(req.params.id);
  const sensor = sensors.find(s => s.id === id);
  
  if (!sensor) {
    return res.status(404).json({ error: 'Capteur non trouvé' });
  }
  
  res.json(sensor);
});

app.post('/sensors/:id/data', (req, res) => {
  const id = parseInt(req.params.id);
  const sensor = sensors.find(s => s.id === id);
  
  if (!sensor) {
    return res.status(404).json({ error: 'Capteur non trouvé' });
  }
  
  if (!req.body.value) {
    return res.status(400).json({ error: 'La valeur est requise' });
  }
  
  // Mise à jour de la valeur du capteur
  sensor.value = req.body.value;
  sensor.timestamp = new Date();
  
  res.json(sensor);
});

app.get('/health', (req, res) => {
  res.json({ status: 'UP', timestamp: new Date() });
});

// Démarrage du serveur
app.listen(port, () => {
  console.log(`API de supervision de capteurs démarrée sur le port ${port}`);
});

module.exports = app;
