const { expect, assert } = require("chai");
const { ethers } = require("hardhat");

let snft;
let vrf;
let grb;
let staker;
let owner;
let addr1;

const BigNumber = ethers.BigNumber;

describe("SNFT", function () {
  beforeEach(async function () {

    const GRB = await ethers.getContractFactory("GRB");
    grb = await GRB.deploy();

    const GRBStaker = await ethers.getContractFactory("GRBStaker");
    staker = await GRBStaker.deploy(grb.address);

    const VRFProvider = await ethers.getContractFactory("VRFProvider");
    vrf = await VRFProvider.deploy();

    const SNFTcontract = await ethers.getContractFactory("SNFT");
    snft = await SNFTcontract.deploy(grb.address, vrf.address, staker.address);

    await vrf.setSNFT(snft.address);

    await snft.initializeUser();


    await grb.transfer(snft.address, '1000000000000000000000000');

    [owner, addr1] = await ethers.getSigners();
  });

  it("SNFT has grb", async function () {
    let balanceContract = await grb.balanceOf(snft.address);
    expect(balanceContract.toString()).to.equal('1000000000000000000000000');
  });

  it("Can create free ship", async function () {
    let fleet = await snft.getUserFleet(owner.address);
    expect(fleet.length).to.equal(1);
    await snft.createTestShipForFree();
    fleet = await snft.getUserFleet(owner.address);
    expect(fleet.length).to.equal(2);
  });

  it("Can explore and spend fuel", async function () {
    let fuel = await snft.balanceOf(owner.address, 2);
    expect(fuel.toString()).to.equal('5');
    let userExplorationStatus = await snft.userExplorationStatus(owner.address);
    expect(userExplorationStatus.fleetOnExplore).to.equal(false);
    await snft.explore(1);
    userExplorationStatus = await snft.userExplorationStatus(owner.address);
    expect(userExplorationStatus.fleetOnExplore).to.equal(true);
    fuel = await snft.balanceOf(owner.address, 2);
    expect(fuel.toString()).to.equal('3');
    //console.log(userExplorationStatus)
  });

  it("Refinery cant produce more than current mineral", async function () {
    let calcRef;

    await ethers.provider.send('evm_increaseTime', [12 * 60 * 60]);
    await ethers.provider.send('evm_mine');

    calcRef= await snft.calculateRefinery();
    let mineralSpent1 = calcRef[0];

    await ethers.provider.send('evm_increaseTime', [12 * 60 * 60]);
    await ethers.provider.send('evm_mine');

    calcRef= await snft.calculateRefinery();
    let mineralSpent2 = calcRef[0];

    expect(mineralSpent1.toString()).to.equal(mineralSpent2.toString());
  });

  it("Refinery produces crystal", async function () {
    let mineral = await snft.balanceOf(owner.address, 0);
    expect(mineral.toString()).to.equal('5000000000000000000');
    let crystal = await snft.balanceOf(owner.address, 1);
    expect(crystal.toString()).to.equal('0');
    let refinery = await snft.userRefinery(owner.address);
    //console.log(refinery);
    let calcRef = await snft.calculateRefinery();
    //console.log(calcRef);

    await ethers.provider.send('evm_increaseTime', [24 * 60 * 60]);
    await ethers.provider.send('evm_mine');

    await snft.claimRefinery();
    //console.log(calcRef);
    mineral = await snft.balanceOf(owner.address, 0);
    expect(mineral.toString()).to.equal('0');
    crystal = await snft.balanceOf(owner.address, 1);
    //console.log(crystal);
  });

  it("can upgrade ship - spend crystals", async function () {
    //get crystal
    await ethers.provider.send('evm_increaseTime', [24 * 60 * 60]);
    await ethers.provider.send('evm_mine');
    await snft.claimRefinery();

    let crystal = await snft.balanceOf(owner.address, 1);

    let ship = await snft.spaceshipData(34);

    await snft.upgradeShip(34, 1, 1, 1, 1);

    let ship2 = await snft.spaceshipData(34);

    expect(parseInt(ship.hp)+1).to.equal(parseInt(ship2.hp));
    expect(parseInt(ship.attack)+1).to.equal(parseInt(ship2.attack));
    expect(parseInt(ship.miningSpeed)+1).to.equal(parseInt(ship2.miningSpeed));
    expect(parseInt(ship.travelSpeed)+1).to.equal(parseInt(ship2.travelSpeed));

    let crystal2 = await snft.balanceOf(owner.address, 1);
    expect(crystal.toString()).to.equal(crystal2.add(BigNumber.from('2000000000000000000')).toString());
  });

  it("can upgrade ship - upgrade card", async function () {
    let ship = await snft.spaceshipData(34);

    await snft.createTestUpgradeCardForFree();

    for(let i=22; i<34; i++){
      let haveUpgrade = await snft.balanceOf(owner.address, i);
      if(haveUpgrade > 0)
      {
        await snft.useUpgradeCard(i.toString(), 34);

        let ship2 = await snft.spaceshipData(34);
    
        if(i < 25){
          expect(parseInt(ship.hp)).to.lt(parseInt(ship2.hp));
        }
        else if(i < 28){
          expect(parseInt(ship.attack)).to.lt(parseInt(ship2.attack));
        }
        else if(i < 31){
          expect(parseInt(ship.miningSpeed)).to.lt(parseInt(ship2.miningSpeed));
        }
        else {
          expect(parseInt(ship.travelSpeed)).to.lt(parseInt(ship2.travelSpeed));
        }

        break;
      }
    }
  });

  it("can upgrade refinery - spend crystals", async function () {
    //get crystal
    await ethers.provider.send('evm_increaseTime', [24 * 60 * 60]);
    await ethers.provider.send('evm_mine');
    await snft.claimRefinery();

    let crystal = await snft.balanceOf(owner.address, 1);

    let refinery = await snft.userRefinery(owner.address);
    const production1 = refinery.productionPerSecond;

    await snft.upgradeRefinery(1);

    refinery = await snft.userRefinery(owner.address);
    const production2 = refinery.productionPerSecond;

    expect(production1.toString()).to.equal(production2.div(BigNumber.from('2')).toString());

    let crystal2 = await snft.balanceOf(owner.address, 1);
    expect(crystal.toString()).to.equal(crystal2.add(BigNumber.from('1000000000000000000')).toString());
  });

  it("Can remove/add ship from/to fleet", async function () {
    await snft.createTestShipForFree();
    let isOnFleet = await snft.shipIsOnFleet(35);
    expect(isOnFleet).to.equal(true);

    let fleet = await snft.getUserFleet(owner.address);
    expect(fleet.length).to.equal(2);
    await snft.removeShipFromFleet(35);
    fleet = await snft.getUserFleet(owner.address);
    expect(fleet.length).to.equal(1);

    isOnFleet = await snft.shipIsOnFleet(35);
    expect(isOnFleet).to.equal(false);

    await snft.addShipToFleet(35);

    fleet = await snft.getUserFleet(owner.address);
    expect(fleet.length).to.equal(2);
    isOnFleet = await snft.shipIsOnFleet(35);
    expect(isOnFleet).to.equal(true);
  });

  it("get/use boosterpack", async function () {
    await snft.createTestBoosterPackForFree();

    let boosterPackCount = await snft.balanceOf(owner.address, 3);
    expect(boosterPackCount.toString()).to.equal('1');

    await snft.useBoosterPack();

    boosterPackCount = await snft.balanceOf(owner.address, 3);
    expect(boosterPackCount.toString()).to.equal('0');

  });

  it("can buy GRB", async function () {
    let balanceUser1 = await grb.balanceOf(addr1.address);
    expect(balanceUser1.toString()).to.equal('0');
    await snft.connect(addr1).buyGRB('100000000',{value: '1000000'});
    balanceUser1 = await grb.balanceOf(addr1.address);
    expect(balanceUser1.toString()).to.equal('100000000');
  });

  it("can buy Fuel - spend crystal", async function () {
    //get crystal
    await ethers.provider.send('evm_increaseTime', [24 * 60 * 60]);
    await ethers.provider.send('evm_mine');
    await snft.claimRefinery();

    let crystal = await snft.balanceOf(owner.address, 1);
    let fuel = await snft.balanceOf(owner.address, 2);

    await snft.buyFuel(3);

    let crystal2 = await snft.balanceOf(owner.address, 1);
    let fuel2 = await snft.balanceOf(owner.address, 2);
    expect(crystal.toString()).to.equal(crystal2.add(BigNumber.from('900000000000000000')).toString());
    expect(fuel.add(BigNumber.from('3')).toString()).to.equal(fuel2.toString());
  });

  it("can buy Boosterpack w GRB - no staking", async function () {
    await grb.approve(snft.address, '90000000000000000000000');
    let balance = await grb.balanceOf(owner.address);
    await snft.buyBoosterPackGRB();
    let balance2 = await grb.balanceOf(owner.address);
    const diff = BigNumber.from(balance).sub(BigNumber.from(balance2));
    let boosterPackCount = await snft.balanceOf(owner.address, 3);
    expect(boosterPackCount.toString()).to.equal('1');
    expect(diff.toString()).to.equal('1000000000000000000');
  });

  it("can buy Boosterpack w GRB - w staking", async function () {
    await grb.approve(snft.address, '90000000000000000000000');
    await grb.approve(staker.address, '90000000000000000000000');
    await staker.deposit('10000000000000000000', 1);
    let balance = await grb.balanceOf(owner.address);
    await snft.buyBoosterPackGRB();
    let balance2 = await grb.balanceOf(owner.address);
    const diff = BigNumber.from(balance).sub(BigNumber.from(balance2));
    let boosterPackCount = await snft.balanceOf(owner.address, 3);
    expect(boosterPackCount.toString()).to.equal('1');
    expect(diff.toString()).to.equal('900000000000000000');
  });

  it("can buy Boosterpack w AVAX - spend crystal", async function () {
    await snft.buyBoosterPackAVAX({value:'10000000000000000'});
    let boosterPackCount = await snft.balanceOf(owner.address, 3);
    expect(boosterPackCount.toString()).to.equal('1');
  });

});