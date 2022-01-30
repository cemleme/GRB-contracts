// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

import './GRBStaker.sol';

interface IVRFProvider {
    function getRandom() external returns (uint256);
    function requestRandom() external returns (bytes32);
}

contract SNFT is ERC1155, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public GRBtoken;
    IStaker public staker;
    IVRFProvider public vrf;

    enum ShipType {COMMANDSHIP, BATTLESHIP, MINER, SCOUT, RANDOM}
    enum BoosterRewardType {AVATAR, SHIP, LAND, INVENTORY, CURRENCY, UPGRADE}
    enum ExplorationType {NOTHING, MINERAL, ENCOUNTER}
    enum EncounterType {ABONDONED, AMBUSH, STORM}

    uint256 public maxFleetSize = 4;
    uint256 public initialInventorySlot = 30;
    uint256 public initialRefineryProductionPerSecond = 0.00027 ether; 
    uint256 public initialRefineryConsumptionPerSecond = 0.00054 ether;
    uint256 public initialFuelAmount = 5;
    uint256 public initialMineralAmount = 5 ether;
    uint256 public secondsPerDistance = 18000; //5 hours per distance per speed
    uint256 public secondsPerMining = 18000; //5 hours per 1/miningspeed
    uint256 public upgradeShipStatCrystalCost = 0.5 ether;
    uint256 public upgradeRefineryCrystalCost = 1 ether;
    uint256 public buyFuelCrystalCost = 0.3 ether;
    uint256 public repairCrystalCost = 0.01 ether;
    uint256 public fuelPerDistance = 2;

    uint256 public boosterPackPriceGRB = 1 ether;
    uint256 public priceGRBfromAVAX = 100;

    mapping(address => bool) public userInitialized;
    mapping(address => UserRefinery) public userRefinery; 
    mapping(address => uint256[]) public userFleet;
    mapping(address => uint256[]) public userShips;
    mapping(address => UserData) public userData;
    mapping(address => ExplorationStatus) public userExplorationStatus;
    mapping(uint256 => bool) public shipIsOnFleet;
    mapping(uint256 => uint256) public shipIndexOnFleet;

    struct UserData {
        uint256 inventorySlot;
        uint256 seed;
    }

    struct ExplorationStatus {
        uint256 exploreCompleteTime;
        uint256 currentExplorationDistance;
        uint256 damageTaken;
        uint256 mineralsFound;
        ExplorationType currentExplorationType;
        EncounterType currentEncounterType;
        bool currentMissionFailed;
        bool fleetOnExplore;
    }

    struct UserRefinery {
        uint256 waitingToClaim;
        uint256 productionPerSecond;
        uint256 consumePerSecond;
        uint256 lastUpdateTime;
    }

    struct ShipTypeStats {
        uint256 hpMin;
        uint256 hpMax;
        uint256 attackMin;
        uint256 attackMax;
        uint256 miningSpeedMin;
        uint256 miningSpeedMax;
        uint256 travelSpeedMin;
        uint256 travelSpeedMax;
    }

    mapping(ShipType => uint256) public shipTypeSkinCount;
    mapping(ShipType => ShipTypeStats) public shipTypeStats;

    struct SpaceshipData {
        uint skin;
        uint shipType;
        uint256 hp;
        uint256 attack;
        uint256 miningSpeed;
        uint256 travelSpeed;
    }

    struct SpaceshipStats {
        uint256 hp;
        uint256 attack;
        uint256 miningSpeed;
        uint256 travelSpeed;
    }
    SpaceshipStats public freeCommandshipStats = SpaceshipStats(25, 5, 5, 5);
    mapping(uint => SpaceshipData) public spaceshipData;
    mapping(uint => SpaceshipStats) public upgradeStats;
    
    mapping(bytes32 => uint8) requestToType;

    event ShipCreated(address indexed user, uint256 tokenId, uint256 shiptype, uint256 skin, uint256 hp, uint256 attack, uint256 miningSpeed, uint256 travelSpeed);
    event AvatarCreated(address indexed user, uint256 tokenId, uint256 skin);
    event LandCreated(address indexed user, uint256 tokenId, uint256 skin);
    event BoosterReward(address indexed user, uint8 rewardType, uint256 amount, uint256 timestamp);
    event ShipUpgraded(address indexed user, uint256 upgradeTokenId, uint256 shipTokenId, uint256 timestamp, uint256 hp, uint256 attack, uint256 miningSpeed, uint256 travelSpeed);
    event RefineryUpgraded(address indexed user, uint256 newProduction, uint256 timestamp);
    event AddShipToFleet(address indexed user, uint256 shipTokenId);
    event RemoveShipFromFleet(address indexed user, uint256 shipTokenId);

    uint256 constant AVATAR_SKIN_COUNT = 8;
    uint256 constant LAND_SKIN_COUNT = 10;
    uint256 constant UPGRADE_TYPE_COUNT = 12;
    //CONSUMABLE and FT ids
    uint256 constant MINERAL = 0;
    uint256 constant CRYSTAL = 1;
    uint256 constant FUEL = 2;
    uint256 constant BOOSTER_PACK = 3;
    uint256 constant AVATAR_START = 4;
    uint256 constant LAND_START = AVATAR_START + AVATAR_SKIN_COUNT; //12
    uint256 constant UPGRADE_START = LAND_START + LAND_SKIN_COUNT; //22
    uint256 constant NFT_START = UPGRADE_START + UPGRADE_TYPE_COUNT; //34

    uint256 public lastId = NFT_START;

    constructor() ERC1155("https://9jwlufwrttxr.usemoralis.com:2053/server/functions/metadata?_ApplicationId=dYs1HPZBZwkTGBMw4ksfWnvpE5BZ6nT13LfPmHuU&id={id}") {

        shipTypeStats[ShipType.COMMANDSHIP] = ShipTypeStats(50, 100, 10, 50, 0, 0, 10, 50);
        shipTypeStats[ShipType.BATTLESHIP] = ShipTypeStats(10, 50, 50, 100, 0, 0, 10, 50);
        shipTypeStats[ShipType.MINER] = ShipTypeStats(10, 50, 10, 50, 50, 100, 10, 50);
        shipTypeStats[ShipType.SCOUT] = ShipTypeStats(10, 50, 10, 50, 0, 0, 50, 100);

        shipTypeSkinCount[ShipType.COMMANDSHIP] = 2;
        shipTypeSkinCount[ShipType.BATTLESHIP] = 6;
        shipTypeSkinCount[ShipType.MINER] = 5;
        shipTypeSkinCount[ShipType.SCOUT] = 15;

        upgradeStats[0] = SpaceshipStats(5,0,0,0);
        upgradeStats[1] = SpaceshipStats(10,0,0,0);
        upgradeStats[2] = SpaceshipStats(15,0,0,0);
        upgradeStats[3] = SpaceshipStats(0,5,0,0);
        upgradeStats[4] = SpaceshipStats(0,10,0,0);
        upgradeStats[5] = SpaceshipStats(0,15,0,0);
        upgradeStats[6] = SpaceshipStats(0,0,5,0);
        upgradeStats[7] = SpaceshipStats(0,0,10,0);
        upgradeStats[8] = SpaceshipStats(0,0,15,0);
        upgradeStats[9] = SpaceshipStats(0,0,0,5);
        upgradeStats[10] = SpaceshipStats(0,0,0,10);
        upgradeStats[11] = SpaceshipStats(0,0,0,15);
    }

    function initializeUser() public {
        require(!userInitialized[msg.sender], 'user already initialized');
        userInitialized[msg.sender] = true;
        uint256 randomNumber = vrf.getRandom();
        uint random1 = randomNumber % 100;
        uint random2 = randomNumber % 10000;
        createFreeCommandship(msg.sender, random1);
        createAvatar(msg.sender, random2);
        userData[msg.sender].inventorySlot = initialInventorySlot;
        userRefinery[msg.sender] = UserRefinery(0, initialRefineryProductionPerSecond, initialRefineryConsumptionPerSecond, block.timestamp);
        userExplorationStatus[msg.sender].exploreCompleteTime = block.timestamp;
        _mint(msg.sender, FUEL, initialFuelAmount, "");
        _mint(msg.sender, MINERAL, initialMineralAmount, "");
    }


    modifier onlyVRF() {
        require(msg.sender == address(vrf), "not the vrfProvider");
        _;
    }

    //----------------------
    // UPDATE FUNCTIONS - Owner Only
    //----------------------
    function setVrf(address _vrf) external onlyOwner {
        vrf = IVRFProvider(_vrf);
    }

    function setGRBToken(address _grb) external onlyOwner {
        GRBtoken = IERC20(_grb);
    }

    function setStaker(address _staker) external onlyOwner {
        staker = IStaker(_staker);
    }

    function updateInitialInventorySlot(uint _initialInventorySlot) external onlyOwner {
        initialInventorySlot = _initialInventorySlot;
    }    
    
    function updateInitialRefineryRates(uint _initialRefineryProductionPerSecond, uint _initialRefineryConsumptionPerSecond) external onlyOwner {
        initialRefineryProductionPerSecond = _initialRefineryProductionPerSecond;
        initialRefineryConsumptionPerSecond = _initialRefineryConsumptionPerSecond;
    }

    function updateInitialBalance(uint _initialFuelAmount, uint _initialMineralAmount) external onlyOwner {
        initialFuelAmount = _initialFuelAmount;
        initialMineralAmount = _initialMineralAmount;
    }

    function updateMaxFleetSize(uint _maxFleetSize) external onlyOwner {
        maxFleetSize = _maxFleetSize;
    }

    function updateFreeCommandshipStats(uint hp, uint attack, uint miningSpeed, uint stats) external onlyOwner {
        freeCommandshipStats = SpaceshipStats(hp, attack, miningSpeed, stats);
    }

    function updateBoosterPackPriceGRB(uint _boosterPackPriceGRB) external onlyOwner {
        boosterPackPriceGRB = _boosterPackPriceGRB;
    }

    function updateUpgradeShipStatCrystalCost(uint _upgradeShipStatCrystalCost) external onlyOwner {
        upgradeShipStatCrystalCost = _upgradeShipStatCrystalCost;
    }

    function updateUpgradeRefineryCrystalCost(uint _upgradeRefineryCrystalCost) external onlyOwner {
        upgradeRefineryCrystalCost = _upgradeRefineryCrystalCost;
    }
    //----------------------

    //----------------------
    // UPGRADE FUNCTIONS
    //----------------------

    // statNo: 0:hp, 1:attack, 2:miningSpeed, 3:travelSpeed
    function upgradeShip(uint256 _tokenId, uint256 hpUpgradeCount, uint256 attackUpgradeCount, uint256 miningUpgradeCount, uint256 travelUpgradeCount) external nonReentrant {
        uint256 totalCost = upgradeShipStatCrystalCost * (hpUpgradeCount + attackUpgradeCount + miningUpgradeCount + travelUpgradeCount);
        require(balanceOf(msg.sender, _tokenId) == 1, 'ship doesnt belong to the user');
        require(balanceOf(msg.sender, CRYSTAL) >= totalCost, 'you dont have enough crystal');
        
        _burn(msg.sender, CRYSTAL, totalCost);
        spaceshipData[_tokenId].hp +=  hpUpgradeCount;
        spaceshipData[_tokenId].attack +=  attackUpgradeCount;
        spaceshipData[_tokenId].miningSpeed +=  miningUpgradeCount;
        spaceshipData[_tokenId].travelSpeed +=  travelUpgradeCount;
        emit ShipUpgraded(msg.sender, 0, _tokenId, block.timestamp, hpUpgradeCount, attackUpgradeCount, miningUpgradeCount, travelUpgradeCount);
    }

    function upgradeRefinery(uint256 upgradeCount) external updateRefineryData nonReentrant {
        require(balanceOf(msg.sender, CRYSTAL) >= upgradeRefineryCrystalCost * upgradeCount, 'you dont have enough crystal');
        _burn(msg.sender, CRYSTAL, upgradeRefineryCrystalCost * upgradeCount);
        userRefinery[msg.sender].productionPerSecond += initialRefineryProductionPerSecond * upgradeCount;
        emit RefineryUpgraded(msg.sender, userRefinery[msg.sender].productionPerSecond, block.timestamp);
    }
    //----------------------


    //----------------------
    // SHOP FUNCTIONS 
    //----------------------
    function buyFuel(uint256 _amount) external nonReentrant {
        require(balanceOf(msg.sender, CRYSTAL) >= _amount * buyFuelCrystalCost, 'you dont have enough crystal');
        _burn(msg.sender, CRYSTAL, _amount * buyFuelCrystalCost);
        _mint(msg.sender, FUEL, _amount, '');
    }

    function repairDamage(uint256 _damage) internal nonReentrant {
        require(balanceOf(msg.sender, CRYSTAL) >= _damage * repairCrystalCost, 'you dont have enough crystal');
        _burn(msg.sender, CRYSTAL, _damage * repairCrystalCost);
    }

    function buyGRB(uint256 _amountGRB) external payable nonReentrant {
        require(msg.value >= _amountGRB / priceGRBfromAVAX, 'you need to send correct GRB-AVAX value');
        GRBtoken.safeTransfer(msg.sender, _amountGRB);
    }

    //----------------------


    //----------------------
    // EXPLORE FUNCTIONS 
    //----------------------
    function fleetPower() public view returns(uint, uint, uint, uint, uint) {
        uint hp;
        uint attack;
        uint miningSpeed;
        uint travelSpeed;

        for(uint i=0; i < userFleet[msg.sender].length; i++){
            uint shipId = userFleet[msg.sender][i];
            SpaceshipData memory stats = spaceshipData[shipId];
            hp += stats.hp;
            attack += stats.attack;
            miningSpeed += stats.miningSpeed;
            travelSpeed += stats.travelSpeed;
        }

        return (hp, attack, miningSpeed, travelSpeed, hp + attack);
    }

    function explore(uint256 _distance) external nonReentrant {
        ExplorationStatus storage status = userExplorationStatus[msg.sender];
        require(!status.fleetOnExplore, 'your fleet is already on exploration');
        require(balanceOf(msg.sender, FUEL) >= _distance * fuelPerDistance, 'you dont have enough fuel');
        _burn(msg.sender, FUEL, _distance * fuelPerDistance);
        status.fleetOnExplore = true;
        status.currentExplorationDistance = _distance;
        status.mineralsFound = 0;
        status.damageTaken = 0;
        uint256 rnd = vrf.getRandom();
        //bytes32 requestId = requestRandomness(keyHash, fee);
        //requestToType[requestId] = 0;
        fulfillExplore(rnd);
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomNumber) external onlyVRF {
        //type 0 explore, 1 boosterpack
        if(requestToType[requestId] == 0){
            fulfillExplore(randomNumber);
        }
        else if(requestToType[requestId] == 1){
            fulfillBoosterPack(randomNumber);
        }
    }

    function fulfillExplore(uint256 _random) internal {
        (uint hp,, uint miningSpeed, uint travelSpeed, uint power) = fleetPower();

        uint256 _distance = userExplorationStatus[msg.sender].currentExplorationDistance;
       
        ExplorationStatus storage explorationStatus = userExplorationStatus[msg.sender];
        uint256 randomNumber = _random % 100;
        //check fleet travelSpeed to decrease timer
        explorationStatus.exploreCompleteTime = block.timestamp + _distance * secondsPerDistance / travelSpeed;

        if(randomNumber < 10){ //10% nothing happens
            explorationStatus.currentExplorationType = ExplorationType.NOTHING;
        }
        else if(randomNumber < 61){ //51% mineral node
            explorationStatus.currentExplorationType = ExplorationType.MINERAL;
            if(miningSpeed == 0) explorationStatus.currentMissionFailed = true;
            else{
                explorationStatus.currentMissionFailed = false;
                explorationStatus.mineralsFound = 3**_distance * 1 ether;
                //add mining duration
                explorationStatus.exploreCompleteTime += secondsPerMining / miningSpeed;
            }
        }
        else{ // 39% encounter
            explorationStatus.currentExplorationType = ExplorationType.ENCOUNTER;

            if(randomNumber < 61 + 15){ //15% abondoned mine
                explorationStatus.currentEncounterType = EncounterType.ABONDONED;
                explorationStatus.mineralsFound = 2**_distance * 1 ether;
            }
            else if(randomNumber < 61 + 29){ //14% ambush
                explorationStatus.currentEncounterType = EncounterType.AMBUSH;
                uint256 randomNumberFight = _random / 100000000 % 100000000;
                bool won = fightEnemy(power, _distance, randomNumberFight);
                explorationStatus.currentMissionFailed = !won;
                if(won){
                    explorationStatus.mineralsFound = 4**_distance * 1 ether;
                    explorationStatus.damageTaken += _distance * hp / 20;
                }
                else
                    explorationStatus.damageTaken += _distance * hp / 10;
            }
            else if(randomNumber < 61 + 29){ //10% storm
                explorationStatus.currentEncounterType = EncounterType.STORM;
                explorationStatus.damageTaken += _distance * hp / 10;
            }
        }
    }

    function claimExploration() external nonReentrant {
        ExplorationStatus storage explorationStatus = userExplorationStatus[msg.sender];
        require(explorationStatus.fleetOnExplore, 'your fleet is not on exploration');
        require(explorationStatus.exploreCompleteTime <= block.timestamp, 'exploration is not complete yet');
        explorationStatus.fleetOnExplore = false;
        
        if(explorationStatus.mineralsFound > 0)
            mintMineral(explorationStatus.mineralsFound);
        if(explorationStatus.damageTaken > 0)
            repairDamage(explorationStatus.damageTaken);
    }

    function fightEnemy(uint _power, uint _distance, uint _random) internal pure returns (bool) {
        uint powerRange;
        if(_power <= 100) powerRange = 0;
        else if(_power <=300) powerRange = 1;
        else if(_power <=1000) powerRange = 2;
        else powerRange = 3;

        uint winChance;
        if(_distance == 1) winChance = 70 + powerRange * 10;
        else if(_distance == 2) winChance = 50 + powerRange * 10;
        else if(_distance == 3) winChance = 25 + powerRange * 10;
        else if(_distance == 4) winChance = 1 + powerRange * 10;
        else{
            if(powerRange == 0) winChance = 1;
            else if(powerRange == 1) winChance = 1;
            else if(powerRange == 2) winChance = 11;
            else if(powerRange == 3) winChance = 20;
        }

        return _random <= winChance;
    }
    //----------------------


    //update refinery before claimRefinery, mintMineral and upgradeRefinery to prevent changing the outcome
    modifier updateRefineryData {
        UserRefinery storage refinery = userRefinery[msg.sender];
        uint secondsPassed = block.timestamp - refinery.lastUpdateTime;
        uint mineralSpenditure = secondsPassed * refinery.consumePerSecond;
        uint mineralBalance = balanceOf(msg.sender, MINERAL);
        if(mineralBalance < mineralSpenditure){
            mineralSpenditure = mineralBalance;
        }

        _burn(msg.sender, MINERAL, mineralSpenditure);
        refinery.lastUpdateTime = block.timestamp;
        refinery.waitingToClaim += (mineralSpenditure / refinery.consumePerSecond) * refinery.productionPerSecond;
        _;
    }

    function mintMineral(uint256 _amount) internal updateRefineryData {
        _mint(msg.sender, MINERAL, _amount, "");
    }

    function calculateRefinery() external view returns(uint, uint) {
        UserRefinery memory refinery = userRefinery[msg.sender];
        uint secondsPassed = block.timestamp - refinery.lastUpdateTime;
        uint mineralSpenditure = secondsPassed * refinery.consumePerSecond;
        uint mineralBalance = balanceOf(msg.sender, MINERAL);
        if(mineralBalance < mineralSpenditure){
            mineralSpenditure = mineralBalance;
        }
        return (mineralSpenditure, (mineralSpenditure / refinery.consumePerSecond) * refinery.productionPerSecond);
    }

    function claimRefinery() external updateRefineryData nonReentrant {
        UserRefinery storage refinery = userRefinery[msg.sender];
        uint256 amount = refinery.waitingToClaim;
        refinery.waitingToClaim = 0;
        _mint(msg.sender, CRYSTAL, amount, "");
    }

    function addShipToFleet(uint _tokenId) external {
        require(balanceOf(msg.sender, _tokenId) == 1, 'ship doesnt belong to the user');
        require(!shipIsOnFleet[_tokenId], 'ship is already on the fleet');
        require(userFleet[msg.sender].length < maxFleetSize, 'player fleet is full');
        userFleet[msg.sender].push(_tokenId);
        shipIndexOnFleet[_tokenId] = userFleet[msg.sender].length - 1;
        shipIsOnFleet[_tokenId] = true;

        emit AddShipToFleet(msg.sender, _tokenId);
    }

    function removeShipFromFleet(uint _tokenId) external {
        require(balanceOf(msg.sender, _tokenId) == 1, 'ship doesnt belong to the user');
        require(shipIsOnFleet[_tokenId], 'ship is not on the fleet');       
        userFleet[msg.sender][shipIndexOnFleet[_tokenId]] = userFleet[msg.sender][userFleet[msg.sender].length-1];
        userFleet[msg.sender].pop();
        shipIsOnFleet[_tokenId] = false;
        shipIndexOnFleet[_tokenId] = 0;

        emit RemoveShipFromFleet(msg.sender, _tokenId);
    }

    function getUserShipCount(address _user) external view returns (uint) {
        return userShips[_user].length;
    }

    function getUserShips(address _user) external view returns (uint[] memory) {
        return userShips[_user];
    }
    
    function getUserFleet(address _user) external view returns (uint[] memory) {
        return userFleet[_user];
    }
    
    //----------------------
    // MINT NFT FUNCTIONS 
    //----------------------

    function createAvatar(address user, uint256 randomNumber) internal {
        uint256 skin = randomNumber % AVATAR_SKIN_COUNT;
        uint id = AVATAR_START + skin;

        _mint(user, id, 1, "");

        emit AvatarCreated(user, id, skin);
    }

    function createLand(address user, uint256 randomNumber) internal {
        uint256 skin = randomNumber % LAND_SKIN_COUNT;
        uint id = LAND_START + skin;

        _mint(user, id, 1, "");

        emit LandCreated(user, id, skin);
    }

    function createFreeCommandship(address user, uint256 randomNumber) internal {
        uint256 newId = lastId++;
        uint256 hp = freeCommandshipStats.hp;
        uint256 attack = freeCommandshipStats.attack;
        uint256 miningSpeed = freeCommandshipStats.miningSpeed;
        uint256 travelSpeed = freeCommandshipStats.travelSpeed;
        
        uint256 skin = randomNumber % shipTypeSkinCount[ShipType.COMMANDSHIP];

        spaceshipData[newId] = SpaceshipData(uint256(ShipType.COMMANDSHIP), skin, hp, attack, miningSpeed, travelSpeed);

        _mint(user, newId, 1, "");

        userShips[user].push(newId);
        userFleet[user].push(newId);
        shipIsOnFleet[newId] = true;

        emit ShipCreated(user, newId, uint256(ShipType.COMMANDSHIP), skin, hp, attack, miningSpeed, travelSpeed);
        emit AddShipToFleet(user, newId);
    }

    function createShip(address user, uint256 randomNumber, ShipType shiptype) internal {
        uint256 newId = lastId++;
        
        if(shiptype == ShipType.RANDOM){
            uint random1 = randomNumber % 4;
            if(random1 == 0) shiptype = ShipType.COMMANDSHIP;
            else if(random1 == 1) shiptype = ShipType.BATTLESHIP;
            else if(random1 == 2) shiptype = ShipType.MINER;
            else shiptype = ShipType.SCOUT;
        } 
        ShipTypeStats memory stats = shipTypeStats[shiptype];
        
        uint256 hp = ((randomNumber % ((stats.hpMax - stats.hpMin) * 100)) / 100 ) + stats.hpMin;
        uint256 attack = (randomNumber % ((stats.attackMax - stats.attackMin) * 10000) / 10000) + stats.attackMin;
        uint256 miningSpeed;
        if(shiptype == ShipType.MINER)
            miningSpeed = ((randomNumber % ((stats.miningSpeedMax - stats.miningSpeedMin) * 1000000)) / 1000000 ) + stats.miningSpeedMin;
        uint256 travelSpeed = ((randomNumber % ((stats.travelSpeedMax - stats.travelSpeedMin) * 100000000)) / 100000000 ) + stats.travelSpeedMin;
        uint256 skin = (randomNumber % (shipTypeSkinCount[shiptype] * 10000000000)) / 10000000000;

        spaceshipData[newId] = SpaceshipData(uint256(shiptype), skin, hp, attack, miningSpeed, travelSpeed);

        _mint(user, newId, 1, "");

        userShips[user].push(newId);

        emit ShipCreated(user, newId, uint256(shiptype), skin, hp, attack, miningSpeed, travelSpeed);

        if(userFleet[user].length < maxFleetSize){
            userFleet[user].push(newId);
            shipIsOnFleet[newId] = true;
            emit AddShipToFleet(user, newId);
        }
    }

    function createCommandship() internal {
        uint256 randomNumber = vrf.getRandom();
        createShip(msg.sender, randomNumber, ShipType.COMMANDSHIP);
    }

    function createBattleship() internal {
        uint256 randomNumber = vrf.getRandom();
        createShip(msg.sender, randomNumber, ShipType.BATTLESHIP);
    }

    function createScout() internal {
        uint256 randomNumber = vrf.getRandom();
        createShip(msg.sender, randomNumber, ShipType.SCOUT);
    }

    function createMiner() internal {
        uint256 randomNumber = vrf.getRandom();
        createShip(msg.sender, randomNumber, ShipType.MINER);
    }

    function createRandomShip(address _user) internal {
        uint256 randomNumber = vrf.getRandom();
        createShip(_user, randomNumber, ShipType.RANDOM);
    }

    //----------------------


    //----------------------
    // BOOSTER PACK FUNCTIONS 
    //----------------------

    function buyBoosterPackGRB() external nonReentrant {
        uint price = boosterPackPriceGRB;
        uint stakingLevel = staker.getUserStakingLevel(msg.sender);
        if(stakingLevel > 0) price = price * 9 / 10;
        GRBtoken.safeTransferFrom(msg.sender, address(this), price);
        _mint(msg.sender, BOOSTER_PACK, 1, "");
    }

    function buyBoosterPackAVAX() external payable nonReentrant {
        uint price = boosterPackPriceGRB / priceGRBfromAVAX;
        require(msg.value >= price, 'you need to send correct pack value');
        _mint(msg.sender, BOOSTER_PACK, 1, "");
    }

    function useBoosterPack() external nonReentrant {
        require(balanceOf(msg.sender, BOOSTER_PACK) > 0, 'user doesnt have any booster pack');
        _burn(msg.sender, BOOSTER_PACK, 1);
        uint256 randomNumber = vrf.getRandom();
        //bytes32 requestId = requestRandomness(keyHash, fee);
        //requestToType[requestId] = 1;
        fulfillBoosterPack(randomNumber);
    }

    function fulfillBoosterPack(uint256 _random) internal {
        uint256 totalChance = 138001;

        uint chanceLand = totalChance - 1;
        uint chanceShip = chanceLand - 1000;
        uint chanceCurrency3 = chanceShip - 2000;
        uint chanceCurrency2 = chanceCurrency3 - 5000;
        uint chanceCurrency1 = chanceCurrency2 - 10000;
        uint chanceAvatar = chanceCurrency1 - 10000;
        uint chanceInventorySlot = chanceAvatar - 10000;
        // uint chanceUpgrade = chanceInventorySlot - 100000;

        uint256 boosterRandom = _random % totalChance + 1;

        if(boosterRandom > chanceLand){
            createLand(msg.sender, _random / 1000000000);
            emit BoosterReward(msg.sender, uint8(BoosterRewardType.LAND), 1, block.timestamp);
        }
        else if(boosterRandom > chanceShip){
            createRandomShip(msg.sender);
            emit BoosterReward(msg.sender, uint8(BoosterRewardType.SHIP), 1, block.timestamp);
        }
        else if(boosterRandom > chanceCurrency3){
            rewardCurrency3(msg.sender);
        }
        else if(boosterRandom > chanceCurrency2){
            rewardCurrency2(msg.sender);
        }
        else if(boosterRandom > chanceCurrency1){
            rewardCurrency1(msg.sender);
        }
        else if(boosterRandom > chanceAvatar){
            createAvatar(msg.sender, _random / 1000000000);
            emit BoosterReward(msg.sender, uint8(BoosterRewardType.AVATAR), 1, block.timestamp);
        }
        else if(boosterRandom > chanceInventorySlot){
            rewardInventorySlot(msg.sender);
        }
        else {
            rewardUpgrade(msg.sender, _random / 1000000000);
        }
    }

    function rewardCurrency1(address _user) internal {
        GRBtoken.safeTransfer(_user, boosterPackPriceGRB);
        emit BoosterReward(_user, uint8(BoosterRewardType.CURRENCY), boosterPackPriceGRB, block.timestamp);
    }
    
    function rewardCurrency2(address _user) internal {
        GRBtoken.safeTransfer(_user, 2 * boosterPackPriceGRB);
        emit BoosterReward(_user, uint8(BoosterRewardType.CURRENCY), 2 * boosterPackPriceGRB, block.timestamp);
    }

    function rewardCurrency3(address _user) internal {
        GRBtoken.safeTransfer(_user, 3 * boosterPackPriceGRB);
        emit BoosterReward(_user, uint8(BoosterRewardType.CURRENCY), 3 * boosterPackPriceGRB, block.timestamp);
    }

    function rewardInventorySlot(address _user) internal {
        userData[_user].inventorySlot++;
        emit BoosterReward(_user, uint8(BoosterRewardType.INVENTORY), userData[_user].inventorySlot, block.timestamp);
    }

    function rewardUpgrade(address _user, uint _randomNumber) internal returns (uint id) {
        uint randomNumber = _randomNumber % UPGRADE_TYPE_COUNT;
        id =  UPGRADE_START + randomNumber;
        _mint(msg.sender, id, 1, "");
        emit BoosterReward(_user, uint8(BoosterRewardType.UPGRADE), 1, block.timestamp);
    }

    function useUpgradeCard(uint _upgradeTokenId, uint _shipTokenId) external nonReentrant {
        require(balanceOf(msg.sender, _upgradeTokenId) > 0, 'user doesnt have this upgrade');
        require(balanceOf(msg.sender, _shipTokenId) > 0, 'ship doesnt belong to the user');
        _burn(msg.sender, _upgradeTokenId, 1);
        uint upgradeNo = _upgradeTokenId - UPGRADE_START;
        spaceshipData[_shipTokenId].hp +=  upgradeStats[upgradeNo].hp;
        spaceshipData[_shipTokenId].attack +=  upgradeStats[upgradeNo].attack;
        spaceshipData[_shipTokenId].miningSpeed +=  upgradeStats[upgradeNo].miningSpeed;
        spaceshipData[_shipTokenId].travelSpeed +=  upgradeStats[upgradeNo].travelSpeed;

        emit ShipUpgraded(msg.sender, _upgradeTokenId, _shipTokenId, block.timestamp , upgradeStats[upgradeNo].hp, upgradeStats[upgradeNo].attack, upgradeStats[upgradeNo].miningSpeed, upgradeStats[upgradeNo].travelSpeed);
    }

    //----------------------

    function createTestShipForFree() external {
        createRandomShip(msg.sender);
        emit BoosterReward(msg.sender, uint8(BoosterRewardType.SHIP), 1, block.timestamp);
    }

    function createTestUpgradeCardForFree() external returns (uint id) {
        uint256 randomNumber = vrf.getRandom();
        id = rewardUpgrade(msg.sender, randomNumber);
        emit BoosterReward(msg.sender, uint8(BoosterRewardType.SHIP), 1, block.timestamp);
    }

    function createTestBoosterPackForFree() external {
        _mint(msg.sender, BOOSTER_PACK, 1, "");
    }
}