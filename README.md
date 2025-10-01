# eShop v0.1 - Anonymous Web3 Marketplace (MVP)

A decentralized marketplace enabling anonymous buying and selling of digital goods using cryptocurrency payments through the Polkadot ecosystem.

## 🚧 Current Status: **In Development**

This is a **work-in-progress MVP** for internal Parity usage. Core marketplace features are being implemented according to the PRD.

### ✅ Implemented
- **Session-based anonymous browsing** - Browse products without wallet connection
- **Privacy-preserving cart** - Cart tied to session, not identity
- **Anonymous checkout** - No personal information required
- **Product catalog** - Category-based browsing and search
- **Secure session management** - Crypto-generated session IDs
- **Input validation** - Comprehensive Zod schemas
- **Rate limiting** - DDoS protection
- **WebSocket real-time updates** - Status notifications
- **Database schema** - Ready for marketplace features (users, reputation, transactions)

### 🚧 In Development (See IMPLEMENTATION_ROADMAP.md)
- **Wallet Authentication** - WalletConnect, MetaMask, Talisman, Nova wallet support
- **Google/Github OAuth** - Social login with non-custodial wallet generation
- **Real Blockchain Integration** - Polkadot.js API for DOT/KSM balance checking and transaction monitoring
- **Escrow Smart Contracts** - Multi-signature escrow for secure transactions (Ink! on Substrate)
- **IPFS Integration** - Decentralized metadata storage for products
- **Polkadot Identity** - Display onchain identities for connected wallets
- **Proof-of-Transaction Reputation** - Blockchain-based trust scoring

### ❌ Not in V1 Scope (PRD Limitations)
- Physical goods delivery / anonymous logistics
- Zero-knowledge proof integration
- GDPR compliance tooling
- Traditional payment methods (fiat)
- Decentralized storage (Arweave/Walrus)
- NFT-based product authenticity
- Dispute resolution mechanisms
- Time-locked refunds

## 🎯 Quick Start

### Development

```bash
# Install dependencies
npm install

# Start development servers (frontend + backend)
npm run dev
```

- **Frontend**: http://localhost:3001 (React app)
- **Backend**: http://localhost:3000 (API server)

### Production Build

```bash
npm run build
npm start
```

## 🏗️ Architecture

```
src/
├── server.ts                    # Express server & WebSocket
├── config/
│   ├── constants.ts            # Application configuration
│   └── index.ts               # Polkadot chain configuration
├── frontend/                   # React frontend application
│   ├── components/            # Reusable UI components
│   ├── pages/                # Page components
│   └── hooks/                # Custom React hooks
├── middleware/                # Express middleware
├── models/                    # TypeScript data models
├── routes/                    # API route handlers
├── services/                  # Business logic services
│   ├── databaseService.ts     # SQLite database
│   ├── sessionService.ts      # Session handling
│   ├── cartService.ts         # Cart management
│   ├── productService.ts      # Product CRUD
│   └── anonymousUserService.ts # User reputation
├── validation/                # Zod validation schemas
└── utils/                     # Utility functions
```

## 🔒 Security Features

- **Anonymous User System** - Privacy-preserving user management
- **Secure Session Management** - Crypto-generated session IDs
- **Input Validation** - XSS/injection prevention with Zod
- **Rate Limiting** - Configurable limits per endpoint
- **CORS Security** - Production-ready configuration
- **HttpOnly Cookies** - Secure session storage

## 🛠️ API Endpoints

### Products
- `GET /api/products` - List products with pagination/filtering
- `GET /api/products/:id` - Get single product
- `POST /api/products` - Create product
- `PUT /api/products/:id` - Update product
- `DELETE /api/products/:id` - Delete product

### Categories
- `GET /api/categories` - List categories
- `POST /api/categories` - Create category
- `PUT /api/categories/:id` - Update category
- `DELETE /api/categories/:id` - Delete category

### Shopping Cart
- `GET /api/cart` - Get current cart
- `POST /api/cart/items` - Add item to cart
- `PUT /api/cart/items/:id` - Update cart item
- `DELETE /api/cart/items/:id` - Remove cart item
- `POST /api/cart/clear` - Clear entire cart

### Marketplace (Web3 - In Development)
- `GET /api/marketplace/users` - Get anonymous user profile
- `POST /api/marketplace/users` - Create anonymous user
- `PUT /api/marketplace/users/:id` - Update user reputation

## 🧪 Testing

```bash
npm run test                # Run all tests
npm run test:backend        # Backend unit tests
npm run test:frontend       # Frontend tests
npm run test:coverage       # Coverage report
```

See `tests/README.md` for detailed testing documentation.

## 📊 Database Schema

### Current Tables
- **categories** - Product categories
- **products** - Unified product model (supports marketplace features)
- **carts** - Shopping cart sessions
- **cart_items** - Individual cart items
- **anonymous_users** - User profiles with reputation
- **reputation_events** - Reputation change history

### Planned Tables (For Implementation)
- **marketplace_transactions** - Escrow-based transactions
- **escrow_contracts** - Smart contract tracking

## 📈 Development Roadmap

See `IMPLEMENTATION_ROADMAP.md` for the complete 16-week implementation plan covering:

1. **Weeks 1-2**: Cleanup Phase ✅ (COMPLETED)
2. **Weeks 3-5**: Core Infrastructure (Wallet Auth, Blockchain Integration, IPFS)
3. **Weeks 6-9**: Smart Contracts & Escrow
4. **Weeks 10-12**: Marketplace Features (OAuth, Identity, Reputation)
5. **Weeks 13-14**: Testing & Polish
6. **Weeks 15-16**: Internal Deployment at Parity

## 🔧 Environment Variables

```bash
# Database
DATABASE_PATH=./data/merchant.db

# Security
STRICT_IP_VALIDATION=false
CORS_ORIGIN=http://localhost:3000,http://localhost:3001

# Logging
LOG_LEVEL=info
NODE_ENV=development
```

## 📝 Available Scripts

```bash
npm run dev          # Start development servers
npm run build        # Build both frontend and backend
npm start           # Start production server
npm run lint        # Run ESLint
npm test            # Run all tests
```

## 🤝 Contributing

This is an internal Parity project for V1 MVP. See `CLEANUP_PLAN.md` for the detailed cleanup and implementation strategy.

## 📄 Project Documents

- `CLEANUP_PLAN.md` - Detailed cleanup plan and gap analysis
- `IMPLEMENTATION_ROADMAP.md` - 16-week implementation roadmap
- `tests/README.md` - Testing documentation
- PRD (see project documentation) - Product requirements

## 🙏 Acknowledgments

- Built with [React](https://reactjs.org/) and [Express.js](https://expressjs.com/)
- Crypto payments powered by [Polkadot.js](https://polkadot.js.org/) (to be integrated)
- Database management with [better-sqlite3](https://github.com/WiseLibs/better-sqlite3)
- Input validation with [Zod](https://zod.dev/)
- Security with [Helmet](https://helmetjs.github.io/) and [express-rate-limit](https://github.com/nfriedly/express-rate-limit)

---

**Status**: 🚧 Active Development | **Target**: Internal Parity Usage (Dec 2025) | **Type**: Digital Goods Marketplace MVP
