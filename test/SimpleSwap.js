const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SimpleSwap - Full tests", function () {
  async function deployFixture() {
    const [owner] = await ethers.getSigners();

    // Deploy token contracts
    const TokenA = await ethers.getContractFactory("TokenA");
    const TokenB = await ethers.getContractFactory("TokenB");
    const tokenA = await TokenA.deploy(owner.address);
    const tokenB = await TokenB.deploy(owner.address);

    // Mint tokens
    await tokenA.mint(owner.address, ethers.parseEther("1000"));
    await tokenB.mint(owner.address, ethers.parseEther("1000"));

    // Deploy SimpleSwap
    const SimpleSwap = await ethers.getContractFactory("SimpleSwap");
    const simpleSwap = await SimpleSwap.deploy(owner.address);

    return { simpleSwap, tokenA, tokenB, owner };
  }

  it("should revert getAmountOut if amountIn is zero", async () => {
    const { simpleSwap } = await loadFixture(deployFixture);
    await expect(simpleSwap.getAmountOut(0, 1, 1)).to.be.revertedWith("Amount must be > 0");
  });

  it("should revert getAmountOut with zero reserves", async () => {
    const { simpleSwap } = await loadFixture(deployFixture);
    await expect(simpleSwap.getAmountOut(ethers.parseEther("1"), 0, 0)).to.be.revertedWith("Invalid reserves");
  });

  it("should revert if tokenA and tokenB are the same in addLiquidity", async () => {
    const { simpleSwap, tokenA, owner } = await loadFixture(deployFixture);
    const amount = ethers.parseEther("1");
    const deadline = (await ethers.provider.getBlock("latest")).timestamp + 1000;

    await tokenA.approve(simpleSwap.target, amount);

    await expect(
      simpleSwap.addLiquidity(
        tokenA.target,
        tokenA.target, // Both tokens have the same address
        amount,
        amount,
        0,
        0,
        owner.address,
        deadline
      )
    ).to.be.revertedWith("Identical token addresses");
  });

  it("should revert if tokenA is zero address", async () => {
    const { simpleSwap, tokenB, owner } = await loadFixture(deployFixture);
    const amount = ethers.parseEther("1");
    const deadline = (await ethers.provider.getBlock("latest")).timestamp + 1000;

    await tokenB.approve(simpleSwap.target, amount);

    await expect(
      simpleSwap.addLiquidity(
        ethers.ZeroAddress, // Invalid zero address
        tokenB.target,
        amount,
        amount,
        0,
        0,
        owner.address,
        deadline
      )
    ).to.be.revertedWith("Zero address not allowed");
  });

  it("should revert token swap if path length is not 2", async () => {
    const { simpleSwap, tokenA, owner } = await loadFixture(deployFixture);
    const deadline = (await ethers.provider.getBlock("latest")).timestamp + 1000;
    const amount = ethers.parseEther("1");

    await expect(
      simpleSwap.swapExactTokensForTokens(
        amount,
        0,
        [tokenA.target], // Invalid swap path
        owner.address,
        deadline
      )
    ).to.be.revertedWith("Only 1-step swaps supported");
  });

  it("should add liquidity and mint LP tokens", async () => {
    const { simpleSwap, tokenA, tokenB, owner } = await loadFixture(deployFixture);
    const amountA = ethers.parseEther("100");
    const amountB = ethers.parseEther("200");
    const deadline = (await ethers.provider.getBlock("latest")).timestamp + 1000;

    await tokenA.approve(simpleSwap.target, amountA);
    await tokenB.approve(simpleSwap.target, amountB);

    await simpleSwap.addLiquidity(
      tokenA.target,
      tokenB.target,
      amountA,
      amountB,
      amountA,
      amountB,
      owner.address,
      deadline
    );

    // Check reserve balances against input data
    const [aAdded, bAdded] = await simpleSwap.getReserves(tokenA.target, tokenB.target);
    expect(aAdded).to.equal(amountA);
    expect(bAdded).to.equal(amountB);

    // Check if LP tokens were minted
    const lpBalance = await simpleSwap.balanceOf(owner.address);
    expect(lpBalance).to.be.gt(0);
  });

  it("should mint liquidity using min(liquidityA, liquidityB) when reserves already exist", async () => {
    const { simpleSwap, tokenA, tokenB, owner } = await loadFixture(deployFixture);
    const deadline = (await ethers.provider.getBlock("latest")).timestamp + 1000;

    // Initial balanced ratio of A and B
    const amountA1 = ethers.parseEther("100");
    const amountB1 = ethers.parseEther("100");

    await tokenA.approve(simpleSwap.target, amountA1);
    await tokenB.approve(simpleSwap.target, amountB1);

    // First add liquidity call
    const tx1 = await simpleSwap.addLiquidity(
      tokenA.target,
      tokenB.target,
      amountA1,
      amountB1,
      amountA1,
      amountB1,
      owner.address,
      deadline
    );

    const lpBalanceAfterFirst = await simpleSwap.balanceOf(owner.address);

    // Second add with imbalanced ratio
    const amountA2 = ethers.parseEther("50");
    const amountB2 = ethers.parseEther("80");

    await tokenA.approve(simpleSwap.target, amountA2);
    await tokenB.approve(simpleSwap.target, amountB2);

    const tx2 = await simpleSwap.addLiquidity(
      tokenA.target,
      tokenB.target,
      amountA2,
      amountB2,
      ethers.parseEther("49"),
      ethers.parseEther("40"),
      owner.address,
      deadline
    );

    const lpBalanceAfterSecond = await simpleSwap.balanceOf(owner.address);
    const newLiquidity = lpBalanceAfterSecond - lpBalanceAfterFirst;

    expect(newLiquidity).to.be.gt(0); // Check if new LP tokens were minted in the second call

    // Check if the pool is still balanced
    // This implies that the MIN() liquidity was used
    const [reserveA, reserveB] = await simpleSwap.getReserves(tokenA.target, tokenB.target);
    const expectedRatio = Number(reserveB) / Number(reserveA);
    expect(expectedRatio).to.be.closeTo(1, 0.01);
  });

  it("should calculate price correctly after liquidity is added", async () => {
    const { simpleSwap, tokenA, tokenB, owner } = await loadFixture(deployFixture);
    const amountA = ethers.parseEther("100");
    const amountB = ethers.parseEther("200");
    const deadline = (await ethers.provider.getBlock("latest")).timestamp + 1000;

    await tokenA.approve(simpleSwap.target, amountA);
    await tokenB.approve(simpleSwap.target, amountB);
    await simpleSwap.addLiquidity(
      tokenA.target,
      tokenB.target,
      amountA,
      amountB,
      amountA,
      amountB,
      owner.address,
      deadline
    );

    // Check price calculation based on input amounts
    const price = await simpleSwap.getPrice(tokenA.target, tokenB.target);
    const expectedPrice = (amountB * 10n ** 18n) / amountA;
    expect(price).to.equal(expectedPrice);
  });

  it("should perform a token swap with correct output", async () => {
    const { simpleSwap, tokenA, tokenB, owner } = await loadFixture(deployFixture);
    const amountA = ethers.parseEther("100");
    const amountB = ethers.parseEther("200");
    const amountIn = ethers.parseEther("10");
    const deadline = (await ethers.provider.getBlock("latest")).timestamp + 1000;

    await tokenA.approve(simpleSwap.target, amountA);
    await tokenB.approve(simpleSwap.target, amountB);
    await simpleSwap.addLiquidity(
      tokenA.target,
      tokenB.target,
      amountA,
      amountB,
      amountA,
      amountB,
      owner.address,
      deadline
    );

    await tokenA.approve(simpleSwap.target, amountIn);
    // Use getAmountOut to get the expected output
    const expectedOut = await simpleSwap.getAmountOut(amountIn, amountA, amountB);

    // Do the token swap
    await simpleSwap.swapExactTokensForTokens(
      amountIn,
      expectedOut,
      [tokenA.target, tokenB.target],
      owner.address,
      deadline
    );

    // Address balance should match the expectedOut value
    const balanceB = await tokenB.balanceOf(owner.address);
    expect(balanceB).to.be.gte(expectedOut);
  });

  it("should remove liquidity and return tokenA and tokenB to the provider", async () => {
    const { simpleSwap, tokenA, tokenB, owner } = await loadFixture(deployFixture);
    const amountA = ethers.parseEther("100");
    const amountB = ethers.parseEther("200");
    const deadline = (await ethers.provider.getBlock("latest")).timestamp + 1000;

    // Approve and add liquidity
    await tokenA.approve(simpleSwap.target, amountA);
    await tokenB.approve(simpleSwap.target, amountB);
    await simpleSwap.addLiquidity(
      tokenA.target,
      tokenB.target,
      amountA,
      amountB,
      amountA,
      amountB,
      owner.address,
      deadline
    );

    const lpBalance = await simpleSwap.balanceOf(owner.address);
    expect(lpBalance).to.be.gt(0);

    // Snapshot token balances before removing liquidity
    const beforeA = await tokenA.balanceOf(owner.address);
    const beforeB = await tokenB.balanceOf(owner.address);

    // Approve LP token and remove liquidity
    await simpleSwap.approve(simpleSwap.target, lpBalance);
    await simpleSwap.removeLiquidity(
      tokenA.target,
      tokenB.target,
      lpBalance,
      0,
      0,
      owner.address,
      deadline
    );

    // Check that owner received tokenA and tokenB back
    const afterA = await tokenA.balanceOf(owner.address);
    const afterB = await tokenB.balanceOf(owner.address);

    expect(afterA).to.be.gt(beforeA);
    expect(afterB).to.be.gt(beforeB);
  });
});
