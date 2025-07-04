// Skip TokenA and TokenB from coverage analysis because 
// they are simple wrappers based on OpenZeppelin and not the focus of testing.
module.exports = {
  skipFiles: ["TokenA.sol", "TokenB.sol"]
};