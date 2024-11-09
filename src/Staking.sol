// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

contract Staking {

    // ... more functions implemented here
  
   /**
   * @notice Returns withdrawable balances at exact unlock time
   * @param user address for withdraw
   * @param unlockTime exact unlock time
   * @return amount total withdrawable amount
   * @return penaltyAmount penalty amount
   * @return burnAmount amount to burn
   * @return index of earning
    */
  function ieeWithdrawableBalances(
    address user,
    uint256 unlockTime
  ) internal view returns (uint256 amount, uint256 penaltyAmount, uint256 burnAmount, uint256 index) {
    uint256 length = userEarnings[user].length;
    for (uint256 i; i < length; ) {
      if (userEarnings[user][i].unlockTime == unlockTime) {
        (amount, , penaltyAmount, burnAmount) = _penaltyInfo(userEarnings[user][i]);
        index = i;
        break;
      }
      unchecked {
        i++;
      }
    }
  }

  /**
   * @notice Withdraw individual unlocked balance and earnings, optionally claim pending rewards.
   * @param claimRewards true to claim rewards when exit
   * @param unlockTime of earning
   */ 
  function individualEarlyExit(bool claimRewards, uint256 unlockTime) external {
    address onBehalfOf = msg.sender;
    if (unlockTime <= block.timestamp) revert InvalidTime();
    (uint256 amount, uint256 penaltyAmount, uint256 burnAmount, uint256 index) = ieeWithdrawableBalances(
      onBehalfOf,
      unlockTime
    );

    if (index >= userEarnings[onBehalfOf].length) { 
      return;
    }

    uint256 length = userEarnings[onBehalfOf].length;
    for (uint256 i = index + 1; i < length; ) {
      userEarnings[onBehalfOf][i - 1] = userEarnings[onBehalfOf][i];
      unchecked {
        i++;
      }
    }
    userEarnings[onBehalfOf].pop();

    Balances storage bal = balances[onBehalfOf];
    bal.total = bal.total.sub(amount).sub(penaltyAmount); 
    bal.earned = bal.earned.sub(amount).sub(penaltyAmount);

    _withdrawTokens(onBehalfOf, amount, penaltyAmount, burnAmount, claimRewards);
  }

   // ... rest of functions implemented here
}
