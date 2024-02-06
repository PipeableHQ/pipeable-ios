import express from 'express';
import { timestampLoggingMiddleware } from './timestamp_logging.mjs';

const app = express();
const port = 3000;

// Serve static files from the "public" directory
app.use(express.static('public'));

app.use(timestampLoggingMiddleware);

// Wait the response for :sec seconds to test timeout handling.
app.get('/goto/timeout/:sec', (req, res) => {
    const ms = parseInt(req.params.sec) * 1_000;

    setTimeout(() => {
        res.send(`Waited for ${ms}ms`);
    }, ms);
});

app.listen(port, () => {
    console.log(`Test server running at http://localhost:${port}`);
});
