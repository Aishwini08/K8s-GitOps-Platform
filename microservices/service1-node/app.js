const express = require("express");
const app = express();

app.get("/", (req, res) => {
  res.send("Hello from Node Service 🚀");
});

app.listen(3000, () => {
  console.log("Running on port 3000");
});