import express from 'express';

const app = express();
const port = 3000;

// Serve static files from the "public" directory
app.use(express.static('public'));

// Wait the response for :sec seconds to test timeout handling.
app.get('/goto/timeout/:sec', (req, res) => {
    const ms = parseInt(req.params.sec) * 1_000;

    setTimeout(() => {
        res.send(`Waited for ${ms}ms`);
    }, ms);
});

app.listen(port, () => {
    console.log(`Example app listening at http://localhost:${port}`);
});

// Function to format current timestamp
function getFormattedTimestamp() {
    return new Date().toISOString();
}

// Middleware to log incoming requests
app.use((req, _, next) => {
    const timestamp = getFormattedTimestamp();
    console.log(`[${timestamp}] Received: ${req.method} ${req.url}`);
    next();
});

// Middleware to log when responses are sent
app.use((req, res, next) => {
    const originalSend = res.send;
    res.send = function (body) {
        const timestamp = getFormattedTimestamp();
        console.log(`[${timestamp}] Responded: ${req.method} ${req.url}`);
        originalSend.call(this, body);
    };
    next();
});
