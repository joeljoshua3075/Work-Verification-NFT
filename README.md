# 🛡️ Work Verification NFT

## 📋 Overview

A decentralized work verification system that mints soulbound (non-transferable) NFTs for completed freelance projects. Each NFT serves as immutable proof of work completion, building on-chain reputation for freelancers and providing trust for clients.

## 🌟 Features

- **🔐 Soulbound NFTs**: Non-transferable tokens that stay with freelancers
- **📊 Reputation System**: Automatic reputation scoring based on completed work  
- **⚖️ Dispute Resolution**: DAO-based arbitration for work conflicts
- **📈 Portfolio Tracking**: Complete work history for freelancers and clients
- **💰 Earnings Tracking**: Total earnings accumulation per freelancer
- **🔍 Verification**: On-chain proof of work completion with ratings

## 🚀 Quick Start

### Prerequisites
- Clarinet CLI installed
- Stacks wallet

### Installation
```bash
git clone <repository-url>
cd Work-Verification-NFT
clarinet check
```

## 📝 Contract Functions

### 🎯 Core Functions

#### `mint-work-nft`
```clarity
(mint-work-nft client freelancer job-title job-description rating payment-amount)
```
Mints a new work verification NFT when a project is completed.

**Parameters:**
- `client` - Client's principal address
- `freelancer` - Freelancer's principal address  
- `job-title` - Project title (max 128 chars)
- `job-description` - Project description (max 512 chars)
- `rating` - Work rating (1-5 scale)
- `payment-amount` - Project payment in micro-STX

### 📊 Data Retrieval

#### `get-freelancer-portfolio`
Returns list of all NFT IDs for a freelancer's completed work.

#### `get-client-jobs`
Returns list of all job NFT IDs posted by a client.

#### `get-reputation-score`
Returns comprehensive reputation data including total jobs, average rating, and earnings.

#### `get-work-metadata`
Returns complete metadata for a specific work NFT.

### ⚖️ Dispute System

#### `create-dispute`
```clarity
(create-dispute token-id reason)
```
Initiates a dispute for a specific work NFT.

#### `resolve-dispute`
```clarity
(resolve-dispute dispute-id resolution)
```
Resolves a dispute (DAO/owner only).

### 🔧 Admin Functions

#### `set-dao-address`
Sets the DAO address for dispute resolution.

#### `set-platform-fee`
Updates platform fee (max 10%).

## 💡 Usage Examples

### Minting Work NFT
```clarity
(contract-call? .work-verification-nft mint-work-nft
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 ;; client
  'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE ;; freelancer  
  "Website Development"
  "Built responsive e-commerce website with payment integration"
  u5 ;; 5-star rating
  u1000000) ;; 1 STX payment
```

### Checking Freelancer Stats
```clarity
(contract-call? .work-verification-nft get-freelancer-stats
  'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE)
```

### Creating a Dispute
```clarity
(contract-call? .work-verification-nft create-dispute
  u1 ;; token ID
  "Work not delivered as specified")
```

## 🏗️ Architecture

The contract uses several key data structures:

- **work-metadata**: Core NFT metadata with job details and ratings
- **client-jobs**: Maps client addresses to their posted jobs
- **freelancer-portfolio**: Maps freelancer addresses to completed work
- **reputation-scores**: Aggregated reputation data per freelancer
- **disputes**: Dispute tracking and resolution system

## 🔒 Security Features

- **Access Control**: Only clients or contract owner can mint NFTs
- **Soulbound**: NFTs cannot be transferred, ensuring authentic ownership
- **Dispute Protection**: Multi-party dispute resolution system
- **Data Validation**: Rating bounds checking and proper error handling

## 🛠️ Development

### Running Tests
```bash
npm install
npm test
```

### Deploying
```bash
clarinet integrate
clarinet deploy
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

This project is licensed under the MIT License.

## 🌐 Links

- [Stacks Documentation](https://docs.stacks.co/)
- [Clarinet Documentation](https://docs.hiro.so/stacks/clarinet)
- [Clarity Language Reference](https://docs.stacks.co/clarity)
