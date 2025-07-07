# 🟣 SimpleSwap dApp – Module 4 Project

This repository contains the practical project for **Module 4**, building on the `SimpleSwap` smart contract from Module 3. The goal was to create an interactive front-end and implement automated testing with at least 50% coverage.

---

### Smart Contract Interaction

- A responsive and styled front-end was developed using:
  - **HTML + JavaScript + Ethers.js**
  - [TailwindCSS](https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css)
  - [Font Awesome 6](https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css)

- Features include:
  - Connect to MetaMask wallet
  - Swap **Token A ↔ Token B**
  - Fetch token price using `getPrice`
  - Live price estimate when entering input amount
  - Execute token swaps with **0.5% slippage tolerance**
  - Approve tokens for swap
  - **Mint 1000 TKA and 1000 TKB**

---

### Development Environment & Testing

- Developed using **Hardhat**
- Unit testing with `Chai` and Hardhat Toolbox
- Code coverage measured with: 'npx hardhat coverage'

- ✅ Achieved **≥ 50% test coverage**

---


### Tools Used

- **Front-end:**  
  HTML + JavaScript, TailwindCSS, Font Awesome, Ethers.js

- **Smart Contracts:**  
  Solidity (ERC20s and SimpleSwap)

- **Testing & Dev Environment:**  
  Hardhat, Chai, hardhat-toolbox, hardhat-coverage

---

### 5️⃣ Deployment

- [TKA (Token A)](https://sepolia.etherscan.io/address/0x697abAFb930a37c44F06742915B77CBC67945e09#code)
- [TKB (Token B)](https://sepolia.etherscan.io/address/0xfeB21BD73EcC7B4923A637603312C300ebEE5A9E#code)
- [SimpleSwap Contract](https://sepolia.etherscan.io/address/0x39f15be6161cD3b9E05Ca2a0dAa00BeB7E5D9A15)

- 🔗 **Live dApp on GitHub Pages:**  
  [https://gadgimax.github.io/ETHKIPUMOD4/](https://gadgimax.github.io/ETHKIPUMOD4/)


