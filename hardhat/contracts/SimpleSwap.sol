// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title ETHKIPU MOD 3 - SimpleSwap 
/// @author Gaston Gorosito
/// @notice This contract allows users to add liquidity to a token pair and receive LP tokens.
/// @dev Simplified version inspired by Uniswap V2; LP tokens are minted as ERC20 (TokenL).
contract SimpleSwap is ERC20, Ownable {

    /// @notice Struct for storing token reserves on the pool
    struct Reserve {
        uint reserve0;
        uint reserve1;
    }
    
    /// @notice Mapping to store reserves of each token pair
    /// @dev reserves[token0][token1] = struct with reserve amounts
    mapping(address => mapping(address => Reserve)) private reserves;

    /// @notice Initializes the LP token and sets the contract owner
    /// @param initialOwner Address to be set as the initial owner
    constructor(address initialOwner)
        ERC20("TokenL", "TKL")
        Ownable(initialOwner)
    {}

    /// @notice Sorts two token addresses to maintain canonical order (token0 < token1)
    /// @dev Ensures consistent ordering for storage and lookup; prevents duplicate entries like (A,B) and (B,A)
    /// @param tokenA First token
    /// @param tokenB Second token
    /// @return token0 The lexicographically smaller address
    /// @return token1 The lexicographically larger address
    function sortTokens(address tokenA, address tokenB) private pure returns (address token0, address token1) {
        require(tokenA != tokenB, "Identical token addresses");
        require(tokenA != address(0) && tokenB != address(0), "Zero address not allowed");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    /// @notice Returns the current reserves for a token pair
    /// @param tokenA First token of the pair
    /// @param tokenB Second token of the pair
    /// @return reserveA Reserve amount for tokenA
    /// @return reserveB Reserve amount for tokenB
    function getReserves(address tokenA, address tokenB) public view returns (uint reserveA, uint reserveB) {
        (reserveA, reserveB) = _getReserves(tokenA, tokenB);
    }

    /// @notice Retrieve reserves in canonical order
    /// @dev Sorts token addresses once and returns the correct reserve values.
    /// @param tokenA One of the two tokens in the pair
    /// @param tokenB The other token in the pair
    /// @return reserveA Reserve corresponding to `tokenA`
    /// @return reserveB Reserve corresponding to `tokenB`
    function _getReserves(
        address tokenA,
        address tokenB
    ) internal view returns (uint reserveA, uint reserveB) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        Reserve memory reserve = reserves[token0][token1];
        (reserveA, reserveB) = tokenA == token0
            ? (reserve.reserve0, reserve.reserve1)
            : (reserve.reserve1, reserve.reserve0);
    }

    /// @notice Adds liquidity to a given token pair
    /// @dev Transfers tokens from sender, calculates optimal amounts, and mints LP tokens
    /// @param tokenA First token to supply
    /// @param tokenB Second token to supply
    /// @param amountADesired Desired amount of tokenA
    /// @param amountBDesired Desired amount of tokenB
    /// @param amountAMin Minimum amount of tokenA accepted (slippage check)
    /// @param amountBMin Minimum amount of tokenB accepted (slippage check)
    /// @param to Address to receive LP tokens
    /// @param deadline Timestamp after which the tx is invalid
    /// @return amountA Actual amount of tokenA used
    /// @return amountB Actual amount of tokenB used
    /// @return liquidity LP tokens minted
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity) {
        require(block.timestamp <= deadline, "Deadline expired");
        (uint reserveA, uint reserveB) = _getReserves(tokenA, tokenB);
    
        (amountA, amountB) = _computeLiquidityAmounts(
            reserveA,
            reserveB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );

        // Transfer tokens from sender to this contract
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);

        // Mint LP tokens to provider
        liquidity = calculateLiquidity(amountA, amountB, reserveA, reserveB);
        _mint(to, liquidity);

        // Update pool reserves
        updateReserves(tokenA, tokenB, reserveA + amountA, reserveB + amountB);

    }

    /// @dev Calculates the actual token amounts to be used for maintaining reserve ratio
    /// @param reserveA Current reserve of tokenA
    /// @param reserveB Current reserve of tokenB
    /// @param amountADesired Desired tokenA to contribute
    /// @param amountBDesired Desired tokenB to contribute
    /// @param amountAMin Minimum tokenA accepted
    /// @param amountBMin Minimum tokenB accepted
    /// @return amountA Final tokenA to be used
    /// @return amountB Final tokenB to be used
    function _computeLiquidityAmounts(
        uint reserveA,
        uint reserveB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) private pure returns (uint amountA, uint amountB) {
        // If this is the first liquidity provider (no reserves), accept all desired amounts
        // This will define the initial tokens ratio
        if (reserveA == 0 && reserveB == 0) {
            return (amountADesired, amountBDesired);
        }

        // Calculate how much of tokenB is needed to match the desired amountA while keeping the ratio
        // Derived from: amountBOptimal / amountADesired = reserveB / reserveA to maintain pool ratio
        uint amountBOptimal = (amountADesired * reserveB) / reserveA;

        // If user provided enough (or more) tokenB to match the desired tokenA, use all of A (amountADesired)
        if (amountBOptimal <= amountBDesired) {
            // Ensure tokenB provided is still above minimum required
            require(amountBOptimal >= amountBMin, "Insufficient amountB");
            return (amountADesired, amountBOptimal);
        }

        // Otherwise, calculate how much of tokenA is needed to match the provided tokenB
        uint amountAOptimal = (amountBDesired * reserveA) / reserveB;

        // Ensure tokenA provided is still above minimum required
        require(amountAOptimal >= amountAMin, "Insufficient amountA");
        return (amountAOptimal, amountBDesired);
    }

    /// @notice Updates the reserves for a token pair
    /// @dev Internal function to update bidirectional mapping using canonical order
    /// @param tokenA First token
    /// @param tokenB Second token
    /// @param newReserveA New amount of tokenA in the pool
    /// @param newReserveB New amount of tokenB in the pool
    function updateReserves(address tokenA, address tokenB, uint newReserveA, uint newReserveB) private {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        Reserve storage reserve = reserves[token0][token1];

        // Check if values differ to save gas from writting in storage
        if (tokenA == token0) {
            if (reserve.reserve0 != newReserveA) reserve.reserve0 = newReserveA;
            if (reserve.reserve1 != newReserveB) reserve.reserve1 = newReserveB;
        } else {
            if (reserve.reserve0 != newReserveB) reserve.reserve0 = newReserveB;
            if (reserve.reserve1 != newReserveA) reserve.reserve1 = newReserveA;
        }
    }

    /// @notice Calculates the amount of LP tokens to mint based on current reserves
    /// @dev Follows Uniswap V2 logic: sqrt(amountA * amountB) for first provider, else proportional to existing supply
    /// @param amountA Amount of tokenA being added
    /// @param amountB Amount of tokenB being added
    /// @param reserveA Current reserve of tokenA
    /// @param reserveB Current reserve of tokenB
    /// @return liquidity Amount of LP tokens to mint
    function calculateLiquidity(
        uint amountA,
        uint amountB,
        uint reserveA,
        uint reserveB
    ) private view returns (uint liquidity) {
        uint _totalSupply = totalSupply();

        // Based on: https://app.uniswap.org/whitepaper.pdf
        // 'Initially mints shares equal to the geometric mean of the amounts deposited'
        if (_totalSupply == 0) {
            liquidity = _sqrt(amountA * amountB);
        } else {
            // Check if dividing by zero
            require(reserveA > 0 && reserveB > 0, "Invalid reserves");
            uint liquidityA = (amountA * _totalSupply) / reserveA;
            uint liquidityB = (amountB * _totalSupply) / reserveB;
            // Get the MIN liquidity value
            liquidity = liquidityA < liquidityB ? liquidityA : liquidityB;
        }

        require(liquidity > 0, "Insufficient liquidity minted");
    }

    /// @notice Removes liquidity from the pool, burns liquidity tokens, and returns original tokens
    /// @param tokenA First token to supply
    /// @param tokenB Second token to supply
    /// @param liquidity LP tokens burned
    /// @param amountAMin Minimum amount of tokenA accepted (slippage check)
    /// @param amountBMin Minimum amount of tokenB accepted (slippage check)
    /// @param to Address of receiving user
    /// @param deadline Timestamp after which the tx is invalid
    /// @return amountA for returned token A amount
    /// @return amountB for returned token B amount
    function removeLiquidity(
        address tokenA, 
        address tokenB, 
        uint liquidity, 
        uint amountAMin, 
        uint amountBMin, 
        address to, 
        uint deadline
    ) external returns (uint amountA, uint amountB) {
        require(block.timestamp <= deadline, "Deadline expired");
        uint _totalSupply = totalSupply();

        (uint reserveA, uint reserveB) = _getReserves(tokenA, tokenB);
        // Calculate amount of A & B tokens based on provided liquidity
        amountA = liquidity * reserveA / _totalSupply;
        amountB = liquidity * reserveB / _totalSupply;

        // Check slippage
        require(amountA >= amountAMin, "Min A amount not met");
        require(amountB >= amountBMin, "Min B amount not met");

        // Burn liquidity tokens from user's balance
        _burn(msg.sender, liquidity);

        // Transfer original tokens to the 'to' address
        IERC20(tokenA).transfer(to, amountA);
        IERC20(tokenB).transfer(to, amountB);

        // Update reserves accordingly
        updateReserves(tokenA, tokenB, reserveA - amountA, reserveB - amountB);
    }

    /// @notice Calculates the price of token A in terms of token B
    /// @param tokenA Address of the first token
    /// @param tokenB Address of the second token
    /// @return price token A value expressed in terms of token B
    function getPrice(address tokenA, address tokenB) external view returns (uint price) {
        (uint reserveA, uint reserveB) = _getReserves(tokenA, tokenB);
        require(reserveA > 0, "No liquidity for tokenA");

        // Price of token A in terms of token B (i.e., how many B per 1 A)
        price = reserveB * 1e18 / reserveA;
    }

    /// @notice Calculates how many tokens will be received for a given input amount
    /// @param amountIn Amount of input token
    /// @param reserveIn Reserve of input token in the pool
    /// @param reserveOut Reserve of output token in the pool
    /// @return amountOut Calculated amount of output token to receive
    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) external pure returns (uint amountOut) {
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
    }
    
    /// @notice getAmountOut internal wrapper to reduce gas for internal calls
    function _getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, "Amount must be > 0");
        require(reserveIn > 0 && reserveOut > 0, "Invalid reserves");

        // Formula: amountOut = (amountIn * reserveB) / (reserveA + amountIn)
        amountOut = (amountIn * reserveOut) / (reserveIn + amountIn);
    }

    /// @notice Swap an exact amount of tokenIn for as many tokenOut as possible
    /// @param amountIn Exact amount of input tokens supplied by the caller
    /// @param amountOutMin Minimum acceptable output tokens (slippage protection)
    /// @param path [tokenIn, tokenOut] only length-2 is supported in this version
    /// @param to Recipient of tokenOut
    /// @param deadline Timestamp after which the tx is invalid
    /// @return amounts [amountIn, amountOut] for convenience
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(block.timestamp <= deadline, "Deadline expired");
        require(path.length == 2, "Only 1-step swaps supported");

        address tokenIn  = path[0];
        address tokenOut = path[1];

        // Get token reserves
        (uint reserveIn, uint reserveOut) = _getReserves(tokenIn, tokenOut);
        require(reserveIn > 0 && reserveOut > 0, "No liquidity");

        // Calculate output
        uint amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut >= amountOutMin, "Insufficient output amount");

        // Transfer tokens from user to pool
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Transfer tokens from pool to user
        IERC20(tokenOut).transfer(to, amountOut);

        // Update reserves
        updateReserves(tokenIn, tokenOut, reserveIn + amountIn, reserveOut - amountOut);

        amounts = new uint[](2) ;
        amounts[0] = amountIn;
        amounts[1] = amountOut;
        return amounts;
    }

    /// @notice Computes the integer square root of a given number
    /// @dev Uses the Babylonian method as implemented in Uniswap V2 (see: https://github.com/Uniswap/v2-core/blob/v1.0.1/contracts/libraries/Math.sol)
    /// @param y The input value
    /// @return z The largest integer such that z*z <= y
    function _sqrt(uint y) private pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        } else {
            z = 0; // In case y == 0
        }
    }
}
