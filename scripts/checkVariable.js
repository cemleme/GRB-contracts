async function main() {
    const [deployer] = await ethers.getSigners();
  
    const SNFT = await ethers.getContractFactory("SNFT");
    const snft = await SNFT.attach("0x87FCcb47B78F24Ee0fDFFEDC7A4023c2d9c16B5b");
  
    const data = await snft.calculateRefinery();
    console.log(data);
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });