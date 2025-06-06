pragma solidity >=0.4.21 <0.6.0;

//import "./math/SafeMath.sol";
import './CentralEscrow.sol';
import './DEM.sol';
import './DMValues.sol';

contract DM {
  
  using SafeMath for uint256;

  event onPushMarketPGPPublicKey(string publicKey);  
  event onPushAnnouncement(uint indexed id, bytes title, bytes message);
  event onModifyAnnouncement(uint indexed id, uint8 operator, bytes details);
  event onAddItemDetails(uint indexed igi, uint id, bytes details);
  event onSetItemOfCategory(uint indexed category, uint indexed igi, bytes title, bool isEnabled);
  event onSetItemTag(uint indexed igi, bytes32 indexed lowerCaseHash, bytes32 indexed originalHash, bytes tag, bool isEnabled);
  event onAddDiscountToClient(address indexed vendor, address indexed client, uint indexed igi, uint8 discountRate, bytes additional);
  event onAddBatchOffer(uint indexed igi, bytes details);
  event onAddUserProfile(address indexed user, bytes32 indexed nickNameHash, bytes nickName, bytes about, string publicPGP, bytes additional);
  event onSetFeaturedItem(uint indexed igi, bool isEnabled);
  event onSetFeaturedVendor(address indexed vendor, bool isEnabled);
  event onSetFavourSeller(address indexed buyer, address indexed seller, bool isEnabled);
  event onSetFavourItem(address indexed buyer, uint indexed igi, bool isEnabled);
  event onMessageSent(address indexed sender, address indexed receiver, bytes details);

  modifier adminOnly() {
    if(DMValues(dmValuesAddress).isAdmin(msg.sender)) _; 
  }

  modifier centralEscrowOnly() {
    if(msg.sender == DMValues(dmValuesAddress).centralEscrowAddress()) _;
  }

  struct Item
  {
    uint8 category;
    uint priceUSD;
    bool isActive;
    bytes title;
    uint dealCount;
    uint ratingScore;
    uint quantityLeft;
    bool isQuantityLimited;
    bool isDealPrivate;
    bool isBanned;
    uint noDisputePeriod;
    uint shippingPeriod;
    mapping (address => bool) allowedClients;    
  }

  Item[] public listedItems;

  mapping (address => bool) public sellerBanList;

  // store the global item indice of a vendor
  mapping (address => uint[]) public itemOwners;
  
  // store the item indice of a category
  mapping (uint8 => uint[]) public itemCategories;
  
  address public dmValuesAddress;
  DEM public dem;

  uint public bornTime;

  //mapping (address => uint) public demBuyerDeposits;
  uint public demDepositTotal;

  constructor(address _dmValues) public
  {
    dmValuesAddress = _dmValues;

    bornTime = block.number; 
    
    dem = new DEM(address(this), _dmValues);
  }

  function addUser(bytes memory nickName, bytes32 nickNameHash, bytes memory about, string memory publicPGP, bytes memory additional) public
  {
    emit onAddUserProfile(msg.sender, nickNameHash, nickName, about, publicPGP, additional);
  }

  function addClientDiscount(address client, uint igi, uint8 discountRate, bytes memory details) public
  {
    require(client != address(0));
    emit onAddDiscountToClient(msg.sender, client, igi, discountRate, details);
  }

  function addBatchOffer(uint itemIndex, bytes memory details) public
  {
    uint igi = itemOwners[msg.sender][itemIndex];
    emit onAddBatchOffer(igi, details);
  }

  function setPrivateDealClient(uint itemIndex, address buyer, bool enabled) public
  {
    uint igi = itemOwners[msg.sender][itemIndex];
    Item storage item = listedItems[igi - 1];

    if(item.category > 0)
    {      
      item.allowedClients[buyer] = enabled;
    }
  }

  function enablePrivateDeal(uint itemIndex, bool enabled) public
  {
    uint igi = itemOwners[msg.sender][itemIndex];
    Item storage item = listedItems[igi - 1];

    if(item.category > 0)
    {
      item.isDealPrivate = enabled;
    }
  }

  function isPrivateDealItem(uint igi) public view returns (bool)
  {
    Item storage item = listedItems[igi - 1];
    return item.isDealPrivate;
  }

  function isEligibleBuyer(uint igi, address buyer) public view returns (bool)
  {
    require(buyer != address(0));

    Item storage item = listedItems[igi - 1];

    if(item.isDealPrivate)
    {
      if(item.allowedClients[buyer])
        return true;
      else
        return false;
    }

    return true;
  }

  function isSellerBanned(address seller) view public returns (bool)
  {
    require(seller != address(0));

    if(sellerBanList[seller])
      return true;
    else
      return false;
  }

  function isItemBanned(uint igi) view public returns(bool)
  {
    return listedItems[igi].isBanned;
  }

  function setFavourSeller(address seller, bool isEnabled) public
  {
    require(seller != address(0));
    emit onSetFavourSeller(msg.sender, seller, isEnabled);
  }

  function setFavourItem(uint igi, bool isEnabled) public
  {
    emit onSetFavourItem(msg.sender, igi, isEnabled);
  }

  function sendMessage(address receiver, bytes memory details) public
  {
    emit onMessageSent(msg.sender, receiver, details);
  }

  function getCentralEscrowAddress() public view returns (address){

    return DMValues(dmValuesAddress).centralEscrowAddress();

  }

  function getDEMAddress() public view returns (address){

    return address(dem);

  }

  // add an item
  function addItem(uint8 category, uint priceUSD, bytes memory title, bytes memory details, uint quantityLeft, bool isQuantityLimited, uint noDisputePeriod, uint shippingPeriod) public{
    
    listedItems.push(Item(category, priceUSD, true, title, 0, 0, quantityLeft, isQuantityLimited, false, false, noDisputePeriod, shippingPeriod));

    uint igi = listedItems.length;
    itemOwners[msg.sender].push(igi);
    itemCategories[category].push(igi);

    emit onAddItemDetails(igi, itemOwners[msg.sender].length - 1, details);
    emit onSetItemOfCategory(category, igi, title, true);
  }

  function getNoDisputePeriodOfItem(uint igi) public view returns (uint)
  {
    require(igi <= listedItems.length);

    return listedItems[igi - 1].noDisputePeriod;
  }

  function getShippingPeriodOfItem(uint igi) public view returns (uint)
  {
    require(igi <= listedItems.length);

    return listedItems[igi - 1].shippingPeriod;
  }  

  // return num of items of a vendor
  function numOfItemsOfVendor(address vendor) public view returns (uint){

    if(itemOwners[vendor].length == 0)
      return 0;

    return itemOwners[vendor].length;
  }

  // return num of items of a category
  function numOfItemsOfCategory(uint8 category) public view returns (uint)
  {
    return itemCategories[category].length;
  }

  // ---------------------------------------  
  // DEM functions 
  // ---------------------------------------
  function buyDEM() public payable{

    // price of 1 DEM = 2 ETHERS
    uint demAmount = msg.value.div(2);
    dem.transfer(msg.sender, demAmount);

    demDepositTotal = demDepositTotal.add(demAmount);
  }

  function sellDEM(uint amount) public {

    uint balance = dem.balanceOf(msg.sender);
    require(amount <= balance);

    // return DEMs to fouder
    dem.transferByMarket(msg.sender, address(this), amount);

    // refund ether
    demDepositTotal = demDepositTotal.sub(amount);
    msg.sender.transfer(amount);
  }

  function claimDividend() adminOnly public {

    dem.claimDividend();

  }

  // ---------------------------------------
  // Central escrow only 
  // ---------------------------------------
  // update item's deal count after deal finalization, only executed by central escrow
  function addItemDealCountByOne(uint igi) public centralEscrowOnly{

    Item storage item = listedItems[igi - 1];
    require(item.category != 0);

    item.dealCount = item.dealCount.add(1);
  }

  function addItemRatingScore(uint igi, uint score) public centralEscrowOnly{
    
    Item storage item = listedItems[igi - 1];
    require(item.category != 0);

    item.ratingScore = item.ratingScore.add(score);
  }

  function plusProductQuantity(uint igi, uint count) public centralEscrowOnly{

    Item storage item = listedItems[igi - 1];
    require(item.category != 0);

    item.quantityLeft = item.quantityLeft.add(count);
  }

  function minusProductQuantity(uint igi, uint count) public centralEscrowOnly{

    Item storage item = listedItems[igi - 1];
    require(item.category != 0);

    if(item.quantityLeft < count)
    {
      item.quantityLeft = 0;
    }
    else
    {
      item.quantityLeft = item.quantityLeft.sub(count);
    }
  }

  function rewardDEM(address payable receiver) public payable centralEscrowOnly{

    require(receiver != address(0));

    uint balanceLeft = dem.balanceOf(address(this));
    if(balanceLeft > 0)
    {
      if(msg.value > balanceLeft)
      {
        demDepositTotal = demDepositTotal.add(balanceLeft);
        dem.transfer(receiver, balanceLeft);

        // compensate DEM by ether as don't have enough DEM for reward
        receiver.transfer(msg.value.sub(balanceLeft));
      }
      else
      {
        demDepositTotal = demDepositTotal.add(msg.value);
        dem.transfer(receiver, msg.value);
      }    
    }

  }

  // ---------------------------------------
  // Item edition
  // ---------------------------------------
  function setItemActive(uint id, bool isActive) public returns(bool)
  {
    require(itemOwners[msg.sender].length > 0, "You can only edit your own item.");

    uint igi = itemOwners[msg.sender][id];
    require(igi > 0);

    Item storage item = listedItems[igi - 1];

    if(item.category > 0)
    {
      item.isActive = isActive;
      emit onSetItemOfCategory(item.category, igi, item.title, isActive);

      return true;
    }
    else
      return false;
  }

  function setItemTitle(uint id, bytes memory title) public
  {
    require(itemOwners[msg.sender].length > 0, "You can only edit your own item.");

    uint igi = itemOwners[msg.sender][id];
    require(igi > 0);

    Item storage item = listedItems[igi - 1];

    if(item.category > 0)
      item.title = title;    
  }

  function setItemDetails(uint id, bytes memory details) public
  {
    require(itemOwners[msg.sender].length > 0, "You can only edit your own item.");

    uint igi = itemOwners[msg.sender][id];
    require(igi > 0);

    Item storage item = listedItems[igi - 1];

    if(item.category > 0)
    {
      emit onAddItemDetails(igi, id, details);
    }
  }

  function setItemCategory(uint id, uint8 category) public
  {
    require(itemOwners[msg.sender].length > 0, "You can only edit your own item.");

    uint igi = itemOwners[msg.sender][id];
    require(igi > 0);

    Item storage item = listedItems[igi - 1];

    if(item.category > 0)
    {
      emit onSetItemOfCategory(item.category, igi, '', false);
      item.category = category;
      emit onSetItemOfCategory(item.category, igi, item.title, true);
    }
  }

  function setItemPrice(uint id, uint priceUSD) public
  {
    require(itemOwners[msg.sender].length > 0, "You can only edit your own item.");

    uint igi = itemOwners[msg.sender][id];
    require(igi > 0);

    Item storage item = listedItems[igi - 1];

    if(item.category > 0)
      item.priceUSD = priceUSD;
  }

  function setItemQuantity(uint id, uint quantityLeft, bool isQuantityLimited) public
  {
    require(itemOwners[msg.sender].length > 0, "You can only edit your own item.");

    uint igi = itemOwners[msg.sender][id];
    require(igi > 0);

    Item storage item = listedItems[igi - 1];
  
    if(item.category > 0)
    {
      item.quantityLeft = quantityLeft;
      item.isQuantityLimited = isQuantityLimited;
    }
  }

  function setItemTag(uint id, bytes32 lowerCaseHash, bytes32 originalHash, bytes memory tag, bool isEnabled) public{

    require(itemOwners[msg.sender].length > 0, "You can only edit your own item.");

    uint igi = itemOwners[msg.sender][id];
    require(igi > 0);

    Item storage item = listedItems[igi - 1];

    require(item.category != 0);

    emit onSetItemTag(igi, lowerCaseHash, originalHash, tag, isEnabled);
  }

  function SetNoDisputePeriodOfItem(uint id, uint period) public
  {
    uint igi = itemOwners[msg.sender][id];
    require(igi > 0);

    listedItems[igi - 1].noDisputePeriod = period;
  }

  function SetShippingPeriodOfItem(uint id, uint period) public 
  {
    uint igi = itemOwners[msg.sender][id];
    require(igi > 0);

    listedItems[igi - 1].shippingPeriod = period;
  }

  // ---------------------------------------
  // ---------------------------------------    

  // get the global item index of an item belonging to a vendor, with a local item index
  function getItemGlobalIndex(address vendor, uint itemIndex) public view returns (uint globalItemIndex){

    return itemOwners[vendor][itemIndex];

  }

  // return the item details from a vendor, by given a local index
  function getItemByVendor(address vendor, uint itemIndex) public view returns (uint8, uint, bool, bytes memory, uint, uint, uint, bool, uint){

    uint ii = itemOwners[vendor][itemIndex] - 1;
    return (listedItems[ii].category, listedItems[ii].priceUSD, listedItems[ii].isActive, listedItems[ii].title, listedItems[ii].dealCount, listedItems[ii].ratingScore, listedItems[ii].quantityLeft, listedItems[ii].isQuantityLimited, ii + 1);

  }

  // get an item by given a global item index
  function getItemByGlobal(uint index) public view returns (uint8, uint, bool, bytes memory, uint, uint, uint, bool){

    Item memory item = listedItems[index - 1];
    require(item.category != 0);
    
    return (item.category, item.priceUSD, item.isActive, item.title, item.dealCount, item.ratingScore, item.quantityLeft, item.isQuantityLimited);
  }

  // add a deal to public escrow
  function setupDeal(address payable seller, uint igi, string memory buyerNote, uint quantity, address payable referee) public payable{

    require(sellerBanList[seller] != true && !listedItems[igi - 1].isBanned);

    CentralEscrow centralEscrow = CentralEscrow(getCentralEscrowAddress());
    centralEscrow.addDeal.value(msg.value)(seller, igi, buyerNote, quantity, referee);    

  }

  // add a direct deal to ppublic escrow
  function setupDirectDeal(address payable seller, uint igi, string memory buyerNote, uint quantity) public payable{

    require(sellerBanList[seller] != true && !listedItems[igi - 1].isBanned);

    CentralEscrow centralEscrow = CentralEscrow(getCentralEscrowAddress());
    centralEscrow.addDirectDeal.value(msg.value)(seller, igi, buyerNote, quantity);    

  }

  // ---------------------------------------
  // admin only functions
  // ---------------------------------------
  function setMarketPublicPGP(string memory publicPGP) adminOnly public
  {
    emit onPushMarketPGPPublicKey(publicPGP);
  }

  function pushAnnouncement(uint id, bytes memory title, bytes memory message) adminOnly public
  {
    emit onPushAnnouncement(id, title, message);
  }

  function modifyAnnouncement(uint id, uint8 operator, bytes memory details) adminOnly public
  {
    emit onModifyAnnouncement(id, operator, details);
  }

  function setFeaturedItem(uint igi, bool isEnabled) adminOnly public{
    emit onSetFeaturedItem(igi, isEnabled);
  }

  function setFeaturedVendor(address vendor, bool isEnabled) adminOnly public{

    require(vendor != address(0));
    emit onSetFeaturedVendor(vendor, isEnabled);

  }

  function setSellerBanned(address seller, bool isBanned) adminOnly public{

    require(seller != address(0));
    sellerBanList[seller] = isBanned;

  }

  function setItemBanned(uint igi, bool isBanned) adminOnly public{

    require(listedItems[igi].category > 0);
    listedItems[igi].isBanned = isBanned;

  }

  function transferFund(address payable receiver, uint amount) adminOnly public{

    require(receiver != address(0));
    require(amount <= address(this).balance - demDepositTotal);

    receiver.transfer(amount);

  }

  // ---------------------------------------
  // ---------------------------------------    
  
}