async function main() {
    const [deployer] = await ethers.getSigners();
  
    console.log("Deploying Staker with the account:", deployer.address);

    console.log("Account balance:", (await deployer.getBalance()).toString());
  
    const GRBStaker = await ethers.getContractFactory("GRBStaker");
    const grbStaker = await GRBStaker.deploy();
  
    console.log("GRBStaker address:", grbStaker.address);
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });