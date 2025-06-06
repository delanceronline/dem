pragma solidity >=0.4.21 <0.6.0;

import "./math/SafeMath.sol";
import './DEM.sol';
import './DMValues.sol';
import './DM.sol';

contract CentralEscrowBase {
  
  using SafeMath for uint256;

  event onDealCreated(uint indexed dealIndex, address indexed seller, address indexed buyer, string buyerNote);
  event onDealSetShippingNote(uint indexed dealIndex, string shippingNote);
  event onDealFinalized(address indexed seller, address indexed buyer, uint indexed itemGlobalIndex, uint dealIndex);
  event onDealRatedByBuyer(address indexed seller, uint indexed itemGlobalIndex, uint indexed dealIndex, address buyer, uint8 rating, bytes review);
  event onDealRatedBySeller(address indexed seller, uint indexed itemGlobalIndex, uint indexed dealIndex, address buyer, uint8 rating, bytes review);

  event onDisputeDeal(uint indexed dealIndex, string details);
  event onDisputeResolved(uint indexed dealIndex, bool shouldRefund, uint disputeHandlingFee);


  modifier adminOnly() {
    if(DMValues(dmValuesAddress).isAdmin(msg.sender)) _; 
  }

  modifier marketOnly() {
    if(msg.sender == DMValues(dmValuesAddress).DMAddress()) _;
  }

  modifier moderatorOnly() {
    if(DMValues(dmValuesAddress).isModerator(msg.sender)) _;
  }

  struct Deal{

    //0: buyer
    //1: seller
    //2: referee
    address[3] roles;

    
    //0: activationTime
    //1: shippedTime
    //2: acceptionTime
    //3: disputeExpiredDuration
    //4: totalDisputeExpiredDuration
    //5: itemGlobalIndex
    //6: quantity
    //7: amountTotal
    //8: market commission percent
    //9: shippingPeriod in blocks
    uint[10] numericalData;


    //0: isExtendingDealAllowed
    //1: isShipped
    //2: isFinalized
    //3: isCancelled
    //4: isAccepted
    //5: isDisputed
    //6: isDisputeResolved
    //7: shouldRefund
    //8: isRatedAndReviewedByBuyer
    //9: isRatedAndReviewedBySeller
    //10: isDirectDeal
    bool[11] flags;
    
  }

  // store all deals
  Deal[] internal deals;
  // store the relation of deal owners
  mapping (address => uint[]) public dealOwners;

  // store referee's deals
  mapping (address => uint[]) public refereeDeals;

  // store vendor's specified commission rate
  mapping (address => uint) public vendorCommissionRate;  

  address public dmValuesAddress;

  bool isDirectDealRatingAllowed;

  constructor(address _dmValues) public
  {
    dmValuesAddress = _dmValues;
    isDirectDealRatingAllowed = false;
  }

  function getDEMAddress() public view returns (address){

    return DMValues(dmValuesAddress).DEMAddress();

  }

  function getMarketPlaceAddress() public view returns (address){

    return DMValues(dmValuesAddress).DMAddress();

  }

  // ---------------------------------------
  // admin only functions
  // ---------------------------------------  

  function setDealExtensionAllowed(uint did, bool flag) public adminOnly{

    require(did < deals.length);

    Deal storage deal = deals[did];
    deal.flags[0] = flag;

  }

  function setDirectDealRatingAllowed(bool isAllowed) public adminOnly{

    isDirectDealRatingAllowed = isAllowed;

  }

  // ---------------------------------------
  // ---------------------------------------  
  
  function calculateMarketCommission(uint priceUSD) public view returns (uint)
  {
    DMValues values = DMValues(dmValuesAddress);
    require(values.getMarketplaceCommissionRatesLength() == values.getMarketplaceCommissionBoundsLength());

    uint rate = values.marketplaceCommissionRates(values.getMarketplaceCommissionRatesLength() - 1);
    if(priceUSD <= values.marketplaceCommissionBounds(values.getMarketplaceCommissionBoundsLength() - 1))
    {
      for(uint i = 1; i < values.getMarketplaceCommissionBoundsLength(); i++)
      {
        if(priceUSD >= values.marketplaceCommissionBounds(i - 1) && priceUSD <= values.marketplaceCommissionBounds(i))
        {
          rate = values.marketplaceCommissionRates(i - 1);
          break;
        }
      }
    }

    return rate;
  }

  function addDeal(address payable seller, uint igi, string memory buyerNote, uint quantity, address payable referee) marketOnly public payable{

    DM marketPlace = DM(getMarketPlaceAddress());

    (,uint unitPriceUSD, bool isActive, , , , uint quantityLeft, bool isLimited) = marketPlace.getItemByGlobal(igi);
    
    // isActive --- Only active item can form a deal.
    // quantity <= quantityLeft || !isLimited --- Required quantity should not exceed the inventory.
    // !marketPlace.isPrivateDealItem(igi) || (marketPlace.isPrivateDealItem(igi) && marketPlace.isEligibleBuyer(igi, tx.origin)) --- Must be a public deal item or an eligible buyer for a private deal item.
    require(isActive && (quantity <= quantityLeft || !isLimited) && (!marketPlace.isPrivateDealItem(igi) || (marketPlace.isPrivateDealItem(igi) && marketPlace.isEligibleBuyer(igi, tx.origin))));

    uint priceUSD = unitPriceUSD.mul(quantity);

    Deal memory deal;
    deal.roles[0] = tx.origin;
    deal.roles[1] = seller;
    deal.roles[2] = referee;

    deal.numericalData[0] = block.number;
    deal.numericalData[3] = marketPlace.getNoDisputePeriodOfItem(igi);
    deal.numericalData[4] = marketPlace.getNoDisputePeriodOfItem(igi);
    deal.numericalData[5] = igi;
    deal.numericalData[6] = quantity;
    deal.numericalData[7] = msg.value;
    deal.numericalData[8] = calculateMarketCommission(priceUSD);
    deal.numericalData[9] = marketPlace.getShippingPeriodOfItem(igi);

    deal.flags[0] = true;

    deals.push(deal);
    uint dealIndex = deals.length - 1;

    dealOwners[tx.origin].push(dealIndex);
    dealOwners[seller].push(dealIndex);

    // update product inventory
    marketPlace.minusProductQuantity(igi, quantity);

    emit onDealCreated(dealIndex, seller, tx.origin, buyerNote);
  }

  function addDirectDeal(address payable seller, uint igi, string memory buyerNote, uint quantity) marketOnly public payable{

    (, , bool isActive, , , , uint quantityLeft, bool isLimited) = DM(getMarketPlaceAddress()).getItemByGlobal(igi);

    // isActive --- Only active item can form a deal.
    // quantity <= quantityLeft || !isLimited --- Required quantity should not exceed the inventory.
    // !DM(getMarketPlaceAddress()).isPrivateDealItem(igi) || (DM(getMarketPlaceAddress()).isPrivateDealItem(igi) && DM(getMarketPlaceAddress()).isEligibleBuyer(igi, tx.origin)) --- Must be a public deal item or an eligible buyer for a private deal item.
    require(isActive && (quantity <= quantityLeft || !isLimited) && (DM(getMarketPlaceAddress()).isPrivateDealItem(igi) && DM(getMarketPlaceAddress()).isEligibleBuyer(igi, tx.origin)));

    Deal memory deal;
    deal.roles[0] = tx.origin;
    deal.roles[1] = seller;

    deal.numericalData[0] = block.number;
    deal.numericalData[5] = igi;
    deal.numericalData[6] = quantity;
    deal.numericalData[7] = msg.value;    

    deal.flags[10] = true;

    deals.push(deal);
    uint dealIndex = deals.length - 1;

    dealOwners[tx.origin].push(dealIndex);
    dealOwners[seller].push(dealIndex);

    // update product inventory
    DM(getMarketPlaceAddress()).minusProductQuantity(igi, quantity);

    emit onDealCreated(dealIndex, seller, tx.origin, buyerNote);
  }

  function numOfDeals() public view returns (uint)
  {
    return dealOwners[tx.origin].length;
  }

  function getDealBasicDetails(uint i) public view returns (uint, uint, uint, uint, uint, uint){

    // i < dealOwners[tx.origin].length --- deal count is out of bound.
    require(i < dealOwners[tx.origin].length);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal memory deal = deals[dealIndex];

    return (
      deal.numericalData[6],  // quantity
      deal.numericalData[5],  // item global index
      deal.numericalData[0],  // activation time
      deal.numericalData[7],  // total amount
      deal.numericalData[8],  // market commission percent
      dealIndex
    );

  }

  function getDealBasicDetailsByDealIndex(uint dealIndex) public view returns (uint, uint, uint, uint, uint, uint){
    
    require(dealIndex < deals.length);

    Deal memory deal = deals[dealIndex];

    return (
      deal.numericalData[6],  // quantity
      deal.numericalData[5],  // item global index
      deal.numericalData[0],  // activation time
      deal.numericalData[7],  // total amount
      deal.numericalData[8],  // market commission percent
      dealIndex
    );

  }

  function getDealIndex(uint i) public view returns (uint){

    // i < dealOwners[tx.origin].length --- deal count is out of bound.
    require(i < dealOwners[tx.origin].length);

    return dealOwners[tx.origin][i];
  }

  function getDealGlobalItemIndex(uint i) public view returns (uint){

    // i < dealOwners[tx.origin].length --- deal count is out of bound
    require(i < dealOwners[tx.origin].length);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal memory deal = deals[dealIndex];

    return deal.numericalData[5];
  }

  function readFlag(uint i, uint flagIndex) public view returns (bool){

    // i < dealOwners[tx.origin].length --- deal count is out of bound.
    // flagIndex < 11 --- flag index is out of bound.
    require(i < dealOwners[tx.origin].length && flagIndex < 11);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal memory deal = deals[dealIndex];

    return  deal.flags[flagIndex]; 
  }

  function isDealSeller(uint i) public view returns (bool){

    // i < dealOwners[tx.origin].length --- deal count is out of bound.
    require(i < dealOwners[tx.origin].length);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal memory deal = deals[dealIndex];

    return deal.roles[1] == tx.origin;
  }

  function getDealSeller(uint i) public view returns (address){

    // i < dealOwners[tx.origin].length --- deal count is out of bound.
    require(i < dealOwners[tx.origin].length);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal memory deal = deals[dealIndex];

    return deal.roles[1];
  }

  function isDealBuyer(uint i) public view returns (bool){

    // i < dealOwners[tx.origin].length --- deal count is out of bound.
    require(i < dealOwners[tx.origin].length);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal memory deal = deals[dealIndex];

    return deal.roles[0] == tx.origin;
  }

  function getDealBuyer(uint i) public view returns (address){

    // i < dealOwners[tx.origin].length --- deal count is out of bound.
    require(i < dealOwners[tx.origin].length);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal memory deal = deals[dealIndex];

    return deal.roles[0];  
  }

  function isDealAdmin(uint i) public view returns (bool){

    // i < dealOwners[tx.origin].length --- deal count is out of bound.
    require(i < dealOwners[tx.origin].length);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal memory deal = deals[dealIndex];

    return deal.roles[2] == tx.origin;
  }

  function isDealDisputePeriodExpired(uint i) public view returns (bool){

    // i < dealOwners[tx.origin].length --- deal count is out of bound.
    require(i < dealOwners[tx.origin].length);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal memory deal = deals[dealIndex];

    return (block.number.sub(deal.numericalData[1]) > deal.numericalData[4]);

  }

  function getDisputePeriodRemains(uint i) public view returns (uint){

    // i < dealOwners[tx.origin].length --- deal count is out of bound.
    require(i < dealOwners[tx.origin].length);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal memory deal = deals[dealIndex];

    uint timeElapsed = block.number.sub(deal.numericalData[1]);
    if(timeElapsed < deal.numericalData[4])
    {
      return deal.numericalData[4].sub(timeElapsed);
    }

    return 0;

  }

  function getCancellationPeriodRemains(uint i) public view returns (uint){

    // i < dealOwners[tx.origin].length --- deal count is out of bound.
    require(i < dealOwners[tx.origin].length);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal memory deal = deals[dealIndex];

    if(deal.flags[4])
    {
      uint timeElapsed = block.number.sub(deal.numericalData[2]);

      uint shippingPeriod = DM(getMarketPlaceAddress()).getShippingPeriodOfItem(deal.numericalData[5]);
      if(timeElapsed < shippingPeriod)
      {
        return shippingPeriod.sub(timeElapsed);
      }
    }

    return 0;

  }

  function resolveDispute(uint dealIndex, bool shouldRefund, uint handlingFee) public moderatorOnly {

    require(dealIndex < deals.length);

    Deal storage deal = deals[dealIndex];

    if(deal.numericalData[7] > handlingFee)
    {
      deal.flags[6] = true;
      deal.flags[7] = shouldRefund;

      // restore quantity on held
      DM(getMarketPlaceAddress()).plusProductQuantity(deal.numericalData[5], deal.numericalData[6]);

      emit onDisputeResolved(dealIndex, shouldRefund, handlingFee);

      if(handlingFee > 0)
      {
        deal.numericalData[7] = deal.numericalData[7].sub(handlingFee);
        DMValues(dmValuesAddress).profitCollector().transfer(handlingFee);
      }
    }
  }

  function releaseFunds(Deal storage deal) internal {

    DMValues values = DMValues(dmValuesAddress);

    // pay the seller
    uint rate = vendorCommissionRate[deal.roles[1]];
    if(rate == 0)
      rate = deal.numericalData[8];
    
    address payable seller = address(uint160(deal.roles[1]));
    uint net = deal.numericalData[7].sub((deal.numericalData[7].mul(rate)).div(100));
    seller.transfer(net);
    
    // pool proportation
    uint tokenPoolAmount = ((deal.numericalData[7].sub(net)).mul(values.tokenPoolCommission()).div(100));
    if(tokenPoolAmount > 0)
    {
      // see if any referee
      if(deal.roles[2] != address(0))
      {
        address payable referee = address(uint160(deal.roles[2]));

        // reward 50% to referee in DEM
        uint rewardAmount = tokenPoolAmount.div(2);
        DM(getMarketPlaceAddress()).rewardDEM.value(rewardAmount)(referee);

        // remaining to DEM dividend pool
        (bool b,) = getDEMAddress().call.value(tokenPoolAmount.sub(rewardAmount)).gas(100000)("");
        require(b);
      }
      else
      {
        // no referee for this deal, so pay profit to the token pool for dividends      
        (bool b,) = getDEMAddress().call.value(tokenPoolAmount).gas(100000)("");
        require(b);
      }
    }

    // pay the market
    uint marketAmount = deal.numericalData[7].sub(net).sub(tokenPoolAmount);
    DMValues(dmValuesAddress).profitCollector().transfer(marketAmount);

  }

}