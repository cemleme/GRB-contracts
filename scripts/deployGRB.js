async function main() {
    const [deployer] = await ethers.getSigners();
  
    console.log("Deploying GRB with the account:", deployer.address);

    console.log("Account balance:", (await deployer.getBalance()).toString());
  
    const GRB = await ethers.getContractFactory("GRB");
    const grb = await GRB.deploy();
  
    console.log("GRB address:", grb.address);
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });