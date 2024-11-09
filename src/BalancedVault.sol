pragma solidity 0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "./strategies/Strategy.sol";

contract BalancedVault is Initializable {
    using SafeMath for uint256;

    IERC20 public constant DAI_ADDRESS = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 public constant USDT_ADDRESS = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    ISwapRouter public swapRouter = ISwapRouter(0xe592427a0aece92de3edee1f18e0157c05861564);
    
    // Custom position manager
    INonfungiblePositionManager public positionManager;

    // Track the USDT and DAI balance for each user
    mapping(address => uint256) public userUSDTBalance;
    mapping(address => uint256) public userDAIBalance;
    mapping(address => uint256) public userLastDeposit;

    /// @dev Constructor that disables initializers to prevent direct contract deployment
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializer function to replace the constructor in an upgradeable contract
    /// @param _positionManager Address of the Uniswap V3 Nonfungible Position Manager
    function initialize(
        address _positionManager
    ) public initializer {
        positionManager = INonfungiblePositionManager(_positionManager);
    }

    /// @notice Deposit function to manage a 1:1 USDT:DAI ratio and provide liquidity
    /// @param usdtAmount Amount of USDT to deposit
    /// @param daiAmount Amount of DAI to deposit
    function deposit(uint256 usdtAmount, uint256 daiAmount) external {
        // Make sure at least one of the amounts are not zero
        if (usdtAmount <= 0 && daiAmount == 0) { // TODO: Move this into the assembly block for further optimization
            // Gas optimization via assembly block
            assembly {
                mstore(0, 0x2c5211c6) // error InvalidAmount() -> 0x2c5211c6
                revert(0, 0x04)
            }
        }
        
        // set deadline for withdrawals
        userLastDeposit = block.timestamp + 10 days;

        // Transfer USDT and DAI from the sender to the contract
        usdt.transferFrom(msg.sender, address(this), usdtAmount);
        dai.transferFrom(msg.sender, address(this), daiAmount);

        // Update the user's individual balance tracking
        userUSDTBalance[msg.sender] = userUSDTBalance[msg.sender].add(usdtAmount);
        userDAIBalance[msg.sender] = userDAIBalance[msg.sender].add(daiAmount);

        // Ensure a 1:1 ratio between USDT and DAI in the user's balance
        if (userUSDTBalance[msg.sender] > userDAIBalance[msg.sender]) {
            uint256 excessUSDT = userUSDTBalance[msg.sender].sub(userDAIBalance[msg.sender]);
            _balancePool(address(usdt), address(dai), excessUSDT);
            userUSDTBalance[msg.sender] = userDAIBalance[msg.sender];
        } else {
            uint256 excessDAI = userDAIBalance[msg.sender].sub(userUSDTBalance[msg.sender]);
            _balancePool(address(dai), address(usdt), excessDAI);
            userDAIBalance[msg.sender] = userUSDTBalance[msg.sender];
        }

    }

    function invest() external {
        // After achieving a 1:1 ratio, add liquidity to the Uniswap pool
        Strategy.depositToStrategy(USDT_ADDRESS.balanceOf(address(this)), DAI_ADDRESS.balanceOf(address(this)));
    }

    /// @notice Withdraws in 1:1 USDT:DAI ratio and provide liquidity
    function withdraw() external {
        uint256 withdrawalFee; 
        // avoid calling the function to calculate withdrawal fee if the deadline has already passed
        if (userLastDeposit[msg.sender] >= block.timestamp) {
            withdrawalFee = _calculateWithdrawalFee(); // Basis points (e.g., 3000 = 30%)
        }
        
        // Withdraw USDT and DAI from strategy if needed
        if (IERC20(USDT_ADDRESS).balanceOf(address(this)) <= userUSDTBalance[msg.sender]) {
            Strategy.withdrawFromStrategy(userUSDTBalance[msg.sender], 0);
        }
            
        if (IERC20(DAI_ADDRESS).balanceOf(address(this)) <= userDAIBalance[msg.sender]) {
            Strategy.withdrawFromStrategy(0, userDAIBalance[msg.sender]);
        }

        // Calculate fee-adjusted withdrawal amounts
        uint256 usdtAmount = userUSDTBalance[msg.sender];
        uint256 daiAmount = userDAIBalance[msg.sender];

        // Apply the fee as a percentage of each token amount (withdrawalFee is in basis points)
        uint256 usdtAfterFee = usdtAmount * (1e4 - withdrawalFee) / 1e4;
        uint256 daiAfterFee = daiAmount * (1e4 - withdrawalFee) / 1e4;

        // Transfer the fee-adjusted amounts to the user
        IERC20(USDT_ADDRESS).transfer(msg.sender, usdtAfterFee);
        IERC20(DAI_ADDRESS).transfer(msg.sender, daiAfterFee);

        // Reduce user balances by the original withdrawal amounts
        userUSDTBalance[msg.sender] -= usdtAmount;
        userDAIBalance[msg.sender] -= daiAmount;
    }

    /// @notice calculates the withdrawal fees using a proportional of the days remaining
    /// @return withdrawal fees in basis points
    function _calculateWithdrawalFee() internal returns (uint256 fee) {
        uint256 decayPeriod = 10 days;
        uint256 remainingTime;
        // Initially max fee. The fee decays throughout the thawing period
        fee = 1e4;

        if (userLastDeposit[msg.sender] > block.timestamp) {
           remainingTime = userLastDeposit[msg.sender] - block.timestamp;
           uint256 scaledFee = (remainingTime * 1e4) / decayPeriod;  // Scale up
           fee = scaledFee;  // Scale back down for final fee
        }
    }

    /// @notice Swap tokens on Uniswap V3 to achieve a 1:1 ratio
    /// @param tokenIn The token to swap from
    /// @param tokenOut The token to swap to
    /// @param amountIn The amount of `tokenIn` to swap
    function _balancePool(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal {
        // Approve the swapRouter to spend `tokenIn`
        IERC20(tokenIn).approve(address(swapRouter), amountIn);

        // Set up the Uniswap V3 exact input single params
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 100, // 0.01% fee pool
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0, // flexible slippage to avoid reverts
                sqrtPriceLimitX96: type(uint160).max
            });

        // Perform low level call for gas optimizations
        // Define the function signature for the exactInputSingle call
        bytes4 selector = bytes4(keccak256("exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))"));

        // Encode the parameters into a single `bytes` array
        bytes memory data = abi.encodeWithSelector(
            selector,
            params
        );

        // Execute the swap to balance the ratio to 1:1
        address(swapRouter).call(data);
    }

}

