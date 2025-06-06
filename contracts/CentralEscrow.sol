pragma solidity >=0.4.21 <0.6.0;

import './CentralEscrowBase.sol';
//import "./math/SafeMath.sol";
//import './DEM.sol';

contract CentralEscrow is CentralEscrowBase{
  
  using SafeMath for uint256;

  constructor(address _dmValues) CentralEscrowBase(_dmValues) public
  {
  }

  // seller functions

  function setDealShipped(uint i, string memory shippingNote) public {

    // i < dealOwners[tx.origin].length --- deal count is out of bound.
    require(i < dealOwners[tx.origin].length);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal storage deal = deals[dealIndex];
    require(!deal.flags[1]);

    // !deal.flags[1] && !deal.flags[3] --- Not shipped AND not cancelled
    // tx.origin == deal.roles[1] --- Only seller can ship a deal.
    require(!deal.flags[1] && !deal.flags[3] && tx.origin == deal.roles[1]);
    
    deal.flags[1] = true;
    deal.numericalData[1] = block.number;

    emit onDealSetShippingNote(dealIndex, shippingNote);

    // check if a direct deal, yes then finalize the deal, sending fund to seller.
    if(deal.flags[10])
    {
      deal.flags[2] = true;
      emit onDealFinalized(deal.roles[1], deal.roles[0], deal.numericalData[5], dealIndex);

      DM(getMarketPlaceAddress()).addItemDealCountByOne(deal.numericalData[5]);

      tx.origin.transfer(deal.numericalData[7]);
    }
  }

  function acceptDeal(uint i) public{

    // i < dealOwners[tx.origin].length --- deal count is out of bound.
    require(i < dealOwners[tx.origin].length);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal storage deal = deals[dealIndex];

    // !deal.flags[4] && !deal.flags[3] --- Not accepted yet AND not cancelled
    // tx.origin == deal.roles[1] --- Only seller can accept a deal.
    require(!deal.flags[4] && !deal.flags[3] && tx.origin == deal.roles[1]);

    deal.flags[4] = true;
    deal.numericalData[2] = block.number;

  }

  function rejectDeal(uint i) public{

    // i < dealOwners[tx.origin].length --- deal count is out of bound.
    require(i < dealOwners[tx.origin].length);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal storage deal = deals[dealIndex];

    // !deal.flags[3] && !deal.flags[2] --- Not cancelled AND not finalized
    // tx.origin == deal.roles[1] --- Only seller can refund a deal.
    require(!deal.flags[3] && !deal.flags[2] && tx.origin == deal.roles[1]);

    // restore quantity on held
    DM(getMarketPlaceAddress()).plusProductQuantity(deal.numericalData[5], deal.numericalData[6]);

    if(deal.flags[5])
    {
      // if the deal is already in dispute, resolve it.
      deal.flags[6] = true;
      deal.flags[7] = true;
      emit onDisputeResolved(dealIndex, true, 0);
    }
    else
    {
      // otherwise refund it directly
      deal.flags[3] = true;
      deal.flags[4] = false;

      address payable receiver = address(uint160(deal.roles[0]));
      receiver.transfer(deal.numericalData[7]);
    }
  }

  function finalizeDealWithoutDispute(uint i) public{

    require(i < dealOwners[tx.origin].length, 'deal count is out of bound.');

    uint dealIndex = dealOwners[tx.origin][i];
    Deal storage deal = deals[dealIndex];

    // !deal.flags[2] --- not finalized
    // tx.origin == deal.roles[1] --- Only seller should call this function after safe period.
    // block.number.sub(deal.numericalData[1]) > deal.numericalData[4] --- safe period expired
    // !deal.flags[5] || (deal.flags[6] && !deal.flags[7]) --- Not under dispute or resolved by moderator to sellerz favour
    require(!deal.flags[2] && tx.origin == deal.roles[1] && block.number.sub(deal.numericalData[1]) > deal.numericalData[4] && (!deal.flags[5] || (deal.flags[6] && !deal.flags[7])));
    
    deal.flags[2] = true;
    emit onDealFinalized(deal.roles[1], deal.roles[0], deal.numericalData[5], dealIndex);

    // increase completed deal count by 1
    DM(getMarketPlaceAddress()).addItemDealCountByOne(deal.numericalData[5]);

    releaseFunds(deal);
  }

  // buyer functions

  function extendDealSafeDuration(uint i) public {

    // deal count is out of bound.
    require(i < dealOwners[tx.origin].length);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal storage deal = deals[dealIndex];

    // Extension is allowed AND only buyer can extend a deal AND only can extend a deal after item shipped AND not under dispute AND not finalized.
    require(deal.flags[0] && tx.origin == deal.roles[0] && deal.flags[1] && !deal.flags[5] && !deal.flags[2]);

    uint remains = (deal.numericalData[4].add(deal.numericalData[1])).sub(block.number);
    deal.numericalData[4] = deal.numericalData[4].add(deal.numericalData[3].sub(remains));
  }

  function cancelDeal(uint i) public {

    // deal count is out of bound.
    require(i < dealOwners[tx.origin].length);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal storage deal = deals[dealIndex];

    // !deal.flags[3] && !deal.flags[2] --- Not cancelled AND not finalized
    // tx.origin == deal.roles[0] --- Only buyer can cancel a deal.
    // !deal.flags[4] -> Only can cancel a deal before accepted by seller OR
    // deal.flags[4] && !deal.flags[1] && (block.number - deal.numericalData[2] > deal.numericalData[9]) -> 
    // time from deal accepted should expire shipping period but not shipped yet OR
    // deal.flags[5] && (deal.flags[6] && deal.flags[7]) -> under dispute and resolved by moderator to buyerz favour
    require(!deal.flags[3] && !deal.flags[2] && tx.origin == deal.roles[0] && (!deal.flags[4] || (deal.flags[4] && !deal.flags[1] && (block.number - deal.numericalData[2] > deal.numericalData[9])) || (deal.flags[5] && (deal.flags[6] && deal.flags[7]))));
    
    // refund to buyer
    deal.flags[3] = true;
    address payable buyer = address(uint160(tx.origin));
    buyer.transfer(deal.numericalData[7]);

    // restore quantity on held
    DM(getMarketPlaceAddress()).plusProductQuantity(deal.numericalData[5], deal.numericalData[6]);
  }

  function finalizeDeal(uint i, uint8 rating, bytes memory review) public {

    // deal count is out of bound AND rating score should be greater than zero.
    require(i < dealOwners[tx.origin].length && rating > 0);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal storage deal = deals[dealIndex];

    // !deal.flags[2] && !deal.flags[5] && deal.flags[1] --- Not finalized AND not under dispute AND already shipped
    // tx.origin == deal.roles[0] --- Only buyer can finalize a deal within safe period.
    require(!deal.flags[2] && !deal.flags[5] && deal.flags[1] && tx.origin == deal.roles[0]);

    deal.flags[2] = true;
    emit onDealFinalized(deal.roles[1], deal.roles[0], deal.numericalData[5], dealIndex);

    // update deal rating and review
    deal.flags[8] = true;
    emit onDealRatedByBuyer(deal.roles[1], deal.numericalData[5], dealIndex, deal.roles[0], rating, review);
    DM(getMarketPlaceAddress()).addItemDealCountByOne(deal.numericalData[5]);
    DM(getMarketPlaceAddress()).addItemRatingScore(deal.numericalData[5], rating);

    releaseFunds(deal);

  }

  function submitRatingAndReview(uint i, uint8 rating, bytes memory review) public{

    // 'deal count is out of bound AND rating score should be greater than zero.'
    require(i < dealOwners[tx.origin].length && rating > 0);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal storage deal = deals[dealIndex];

    // !deal.flags[10] || isDirectDealRatingAllowed --- non direct deal or rating is allowed
    // deal.flags[2] --- deal was finalized.
    // tx.origin == deal.roles[0] || tx.origin == deal.roles[1] --- either seller or buyer can rate.
    require((!deal.flags[10] || isDirectDealRatingAllowed) && deal.flags[2] && (tx.origin == deal.roles[0] || tx.origin == deal.roles[1]));

    if(tx.origin == deal.roles[0])
    {
      // buyer rates seller

      // deal was rated.
      require(!deal.flags[8]);

      deal.flags[8] = true;
      emit onDealRatedByBuyer(deal.roles[1], deal.numericalData[5], dealIndex, deal.roles[0], rating, review);
      DM(getMarketPlaceAddress()).addItemRatingScore(deal.numericalData[5], rating);
    }
    else
    {
      // seller rates buyer

      // deal was rated.
      require(!deal.flags[9]);

      deal.flags[9] = true;
      emit onDealRatedBySeller(deal.roles[1], deal.numericalData[5], dealIndex, deal.roles[0], rating, review);      
    }

  }

  function disputeDeal(uint i, string memory details) public {

    // deal count is out of bound.
    require(i < dealOwners[tx.origin].length);

    uint dealIndex = dealOwners[tx.origin][i];
    Deal storage deal = deals[dealIndex];

    // block.number.sub(deal.numericalData[1]) <= deal.numericalData[4] --- Only can raise a dispute within safe period.
    // deal.flags[4] && deal.flags[1] && !deal.flags[2] && !deal.flags[5] --- Order must be accepted by seller AND shipped by seller AND not finalzied AND not under dispute.
    // tx.origin == deal.roles[0] --- Only buyer can dispute a deal within safe period.
    require(block.number.sub(deal.numericalData[1]) <= deal.numericalData[4] && (deal.flags[4] && deal.flags[1] && !deal.flags[2] && !deal.flags[5]) && tx.origin == deal.roles[0]);

    deal.flags[5] = true;
    emit onDisputeDeal(dealIndex, details);

  }

}