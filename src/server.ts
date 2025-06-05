import 'dotenv/config';
import express, { Request, Response, NextFunction } from 'express'; // Corrected import for Request and Response types
import http from 'http';
import WebSocket, { WebSocketServer } from 'ws';
import path from 'path';
import { fileURLToPath } from 'url';
import { App } from './app.js'; // App class will be refactored
import { AlchemyService } from './services/alchemyService.js';

// Resolve __dirname for ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PORT = process.env.PORT || 3000;

// Initialize Express app and HTTP server
const expressApp = express();
const server = http.createServer(expressApp);

// Initialize WebSocket server
const wss = new WebSocketServer({ server });

// Store connected WebSocket clients
const clients = new Set<WebSocket>();

// Main application instance (controls NFC, etc.)
const nfcApp = new App();

// Middleware to parse JSON bodies
expressApp.use(express.json());

// Serve static files from the 'src/web' directory
const webDir = path.join(__dirname, 'web');
expressApp.use(express.static(webDir));
console.log(`🌐 Serving static files from: ${webDir}`);

// Store active payment monitoring sessions
interface PaymentSession {
    amount: number;
    merchantAddress: string;
    startTime: number;
    timeout: NodeJS.Timeout;
}

const activePayments = new Map<string, PaymentSession>();

// WebSocket connection handling
wss.on('connection', (ws) => {
    console.log('🟢 Client connected to WebSocket');
    clients.add(ws);
    ws.send(JSON.stringify({ type: 'status', message: 'Connected to payment terminal.' }));

    ws.on('message', (message) => {
        console.log('💻 Received WebSocket message from client:', message.toString());
    });
    ws.on('close', () => {
        console.log('🔴 Client disconnected from WebSocket');
        clients.delete(ws);
    });
    ws.on('error', (error) => {
        console.error('WebSocket error:', error);
        clients.delete(ws);
    });
});

// Function to broadcast messages to all connected WebSocket clients
export function broadcast(message: object) {
    const data = JSON.stringify(message);
    clients.forEach((client) => {
        if (client.readyState === WebSocket.OPEN) {
            try {
                client.send(data);
            } catch (error) {
                console.error('Error sending message to client:', error);
            }
        }
    });
}

// Explicitly define the async handler type for clarity
type AsyncRequestHandler = (req: Request, res: Response, next?: NextFunction) => Promise<void | Response>;

// Function to monitor transaction for a payment
async function monitorTransaction(merchantAddress: string, amount: number) {
    console.log(`🔍 Starting transaction monitoring for ${merchantAddress}, amount: $${amount}`);
    
    const startTime = Date.now();
    const timeout = setTimeout(() => {
        console.log(`⏰ Payment timeout for ${merchantAddress}`);
        broadcast({ type: 'payment_failure', message: 'Payment timeout - no transaction detected', errorType: 'PAYMENT_TIMEOUT' });
        activePayments.delete(merchantAddress);
    }, 300000); // 5 minutes timeout

    activePayments.set(merchantAddress, {
        amount,
        merchantAddress,
        startTime,
        timeout
    });

    try {
        // Start monitoring transactions to the merchant address
        const unsubscribe = await AlchemyService.monitorTransactions(merchantAddress, async (tx) => {
            console.log(`📝 Transaction detected for ${merchantAddress}:`, tx);
            
            // Verify transaction amount matches expected amount
            if (tx.value >= amount) {
                console.log(`✅ Payment confirmed for ${merchantAddress}`);
                clearTimeout(timeout);
                activePayments.delete(merchantAddress);
                broadcast({ type: 'transaction_confirmed', message: 'Payment confirmed!' });
            }
        });

        // Store unsubscribe function for cleanup
        return unsubscribe;
    } catch (error) {
        console.error('Error setting up transaction monitoring:', error);
        clearTimeout(timeout);
        activePayments.delete(merchantAddress);
        broadcast({ type: 'payment_failure', message: 'Failed to monitor transaction', errorType: 'MONITORING_ERROR' });
        throw error;
    }
}

const initiatePaymentHandler: AsyncRequestHandler = async (req, res) => {
    const { amount, merchantAddress } = req.body;
    if (typeof amount !== 'number' || amount <= 0 || isNaN(amount)) {
        broadcast({ type: 'status', message: 'Invalid amount received from UI.', isError: true });
        res.status(400).json({ error: 'Invalid amount' });
        return;
    }

    if (!merchantAddress || !AlchemyService.isEthereumAddress(merchantAddress)) {
        broadcast({ type: 'status', message: 'Invalid merchant address.', isError: true });
        res.status(400).json({ error: 'Invalid merchant address' });
        return;
    }

    console.log(`💸 Payment initiated for $${amount.toFixed(2)} from Web UI to ${merchantAddress}`);
    broadcast({ type: 'status', message: `Preparing for $${amount.toFixed(2)} payment...` });

    try {
        // Start transaction monitoring
        await monitorTransaction(merchantAddress, amount);
        
        // This method in App will trigger NFCService.armForPaymentAndAwaitTap
        const paymentResult = await nfcApp.processPayment(amount);
        
        if (paymentResult.success) {
            console.log(`✅ Payment successful: ${paymentResult.message}`);
            broadcast({ type: 'payment_success', message: paymentResult.message, amount });
            res.json({ success: true, message: paymentResult.message });
        } else {
            console.log(`❌ Payment failed: ${paymentResult.message}, Type: ${paymentResult.errorType}`);
            broadcast({ type: 'payment_failure', message: paymentResult.message, errorType: paymentResult.errorType });
            const statusCode = paymentResult.errorType === 'PHONE_MOVED_TOO_QUICKLY' ? 409 : 500;
            res.status(statusCode).json({ success: false, message: paymentResult.message, errorType: paymentResult.errorType });
        }
    } catch (error: any) {
        console.error('Error in /initiate-payment endpoint:', error);
        const errorMessage = error.message || 'Internal server error during payment processing.';
        broadcast({ type: 'payment_failure', message: `Server error: ${errorMessage}`, errorType: 'SERVER_ERROR' });
        res.status(500).json({ error: 'Internal server error' });
    }
};

// HTTP endpoint to initiate payment
expressApp.post('/initiate-payment', initiatePaymentHandler);

// Add global error handlers
process.on('uncaughtException', (error) => {
    if (error.message.includes('Cannot process ISO 14443-4 tag')) {
        console.log('💳 Payment card detected - ignoring');
        return;
    }
    console.error('❌ Uncaught Exception:', error);
});

process.on('unhandledRejection', (reason, promise) => {
    console.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
});

// Start the main application logic (NFC, Price Cache)
async function startServerAndApp() {
    try {
        // Initialize AlchemyService first
        try {
            AlchemyService.initialize();
            console.log('✅ AlchemyService initialized successfully');
        } catch (error) {
            console.error('❌ Failed to initialize AlchemyService:', error);
            throw error;
        }

        // Initialize PriceCacheService and start NFC listeners via App class
        await nfcApp.initializeServices(); 
        console.log('🔌 NFC Application services (including Price Cache) initialized.');

        // Start the HTTP server
        server.listen(PORT, () => {
            console.log(`📡 HTTP & WebSocket Server running at http://localhost:${PORT}`);
            console.log(`✅ NFC Payment Terminal is READY. Open http://localhost:${PORT} in your browser.`);
        });

    } catch (error) {
        console.error('❌ Failed to start main application:', error);
        process.exit(1);
    }
}

// Handle graceful shutdown for the server and app services
function shutdown(signal: string) {
    console.log(`\n👋 Received ${signal}. Shutting down gracefully...`);
    
    // Clear all payment monitoring timeouts
    activePayments.forEach((session) => {
        clearTimeout(session.timeout);
    });
    activePayments.clear();
    
    // Close WebSocket clients first
    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.terminate();
        }
    });
    wss.close(() => {
        console.log('🔌 WebSocket server closed.');
    });

    server.close((err) => {
        if (err) {
            console.error('Error closing HTTP server:', err);
        }
        console.log('🛑 HTTP server closed.');
        nfcApp.stopServices();
        process.exit(err ? 1 : 0);
    });

    setTimeout(() => {
        console.error('Timeout: Could not close connections gracefully. Forcefully shutting down.');
        process.exit(1);
    }, 10000);
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

startServerAndApp(); 