async function main() {
    const [deployer] = await ethers.getSigners();
  
    console.log("Deploying contracts with the account:", deployer.address);
  
    console.log("Account balance:", (await deployer.getBalance()).toString());

    //const GRB = await ethers.getContractFactory("GRB");
    //const grb = await GRB.attach("0x1CCB525431A008827dF62fAf70E32894551F86Ba");

    //const GRBStaker = await ethers.getContractFactory("GRBStaker");
    //const staker = await GRBStaker.deploy("0x1CCB525431A008827dF62fAf70E32894551F86Ba");

    const VRFProvider = await ethers.getContractFactory("VRFProvider");
    const vrf = await VRFProvider.attach("0xAA27151dcA6Ae030e5bcD8D551332D4aefF1a8f8");

    const SNFTcontract = await ethers.getContractFactory("SNFT");
    const snft = await SNFTcontract.deploy();

    await vrf.setSNFT(snft.address);
    await snft.setVrf("0xAA27151dcA6Ae030e5bcD8D551332D4aefF1a8f8");
    await snft.setGRBToken("0x1CCB525431A008827dF62fAf70E32894551F86Ba");
    await snft.setStaker("0xf20C70602cE47FeD2b0B427CB48805dbc522F126");


    await snft.initializeUser();
  
    console.log("SNFT address:", snft.address);
    //console.log("VRF address:", vrf.address);
    //console.log("Staker address:", staker.address);
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });