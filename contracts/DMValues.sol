pragma solidity >=0.4.21 <0.6.0;

contract DMValues {
  
  address public DMAddress;
  address public DEMAddress;
  address public centralEscrowAddress;

  uint8 public tokenPoolCommission;

  uint[] public marketplaceCommissionBounds;
  uint[] public marketplaceCommissionRates;

  bool public isDMAddressSet;
  bool public isDEMAddressSet;
  bool public isCentralEscrowAddressSet;

  address payable[] public admins;
  address payable public profitCollector;

  address[] public moderators;

  bytes public moderationContact;
  bytes public marketContact;

  modifier adminOnly() {

    bool isFound = false;
    for(uint i = 0; i < admins.length; i++)
    {
      if(msg.sender == admins[i])
      {
        isFound = true;
        break;
      }
    }

    if(isFound) _;

  }
  
  constructor(address payable _admin, address payable _profitCollector) public
  {
    admins.push(_admin);
    profitCollector = _profitCollector;

    isDMAddressSet = false;
    isDEMAddressSet = false;
    isCentralEscrowAddressSet = false;

    tokenPoolCommission = 60;

    // 4 commission tiers for different deal amount in USD, in wei unit
    marketplaceCommissionBounds.push(0);
    marketplaceCommissionBounds.push(200000000000000000000);
    marketplaceCommissionBounds.push(400000000000000000000);
    marketplaceCommissionBounds.push(800000000000000000000);

    // 4 commission rates, in %
    marketplaceCommissionRates.push(6);
    marketplaceCommissionRates.push(5);
    marketplaceCommissionRates.push(4);
    marketplaceCommissionRates.push(3);

  }

  function setDMAddress(address addr) adminOnly public
  {
    require(!isDMAddressSet);

    DMAddress = addr;
    isDMAddressSet = true;
  }

  function setDEMAddress(address addr) adminOnly public
  {
    require(!isDEMAddressSet);

    DEMAddress = addr;
    isDEMAddressSet = true;
  }

  function setCentralEscrowAddress(address addr) adminOnly public
  {
    require(!isCentralEscrowAddressSet);

    centralEscrowAddress = addr;
    isCentralEscrowAddressSet = true;
  }

  function setTokenPoolCommission(uint8 commission) adminOnly public
  {
    tokenPoolCommission = commission;
  } 

  function setMarketplaceCommissionBound(uint index, uint value) adminOnly public
  {
    require(index < marketplaceCommissionBounds.length);
    marketplaceCommissionBounds[index] = value;
  }

  function setMarketplaceCommissionRate(uint index, uint value) adminOnly public
  {
    require(index < marketplaceCommissionRates.length);
    marketplaceCommissionRates[index] = value;
  }

  function addMarketplaceCommissionBound(uint value) adminOnly public
  {
    marketplaceCommissionBounds.push(value);
  }

  function addMarketplaceCommissionRate(uint value) adminOnly public
  {
    marketplaceCommissionRates.push(value);
  }

  function getMarketplaceCommissionBoundsLength() public view returns (uint)
  {
    return marketplaceCommissionBounds.length;
  }

  function getMarketplaceCommissionRatesLength() public view returns (uint)
  {
    return marketplaceCommissionRates.length;
  }

  function saveModerationContact(bytes memory contact) adminOnly public
  {
    moderationContact = contact;
  }

  function saveMarketContact(bytes memory contact) adminOnly public
  {
    marketContact = contact;
  }

  function setProfitCollector(address payable collector) adminOnly public
  {
    profitCollector = collector; 
  }
  
  function addAdmin(address payable newAdmin) adminOnly public
  {
    admins.push(newAdmin);
  }

  function removeAdmin(address payable oldAdmin) adminOnly public
  {
    for(uint i = 0; i < admins.length; i++)
    {
      if(oldAdmin == admins[i])
      {
        admins[i] = admins[admins.length - 1];
        delete admins[admins.length - 1];
        admins.length--;

        break;
      }
    }
  }

  function getAdminCount() public view returns (uint)
  {
    return admins.length;
  }

  function isAdmin(address payable addr) public view returns (bool)
  {
    for(uint i = 0; i < admins.length; i++)
    {
      if(addr == admins[i])
      {
        return true;
      }
    }

    return false;
  }

  function addModerator(address moderator) public adminOnly{

    require(moderator != address(0));

    moderators.push(moderator);

  }

  function removeModerator(address moderator) public adminOnly{

    for(uint i = 0; i < moderators.length; i++)
    {
      if(moderators[i] == moderator)
      {
        moderators[i] = moderators[moderators.length - 1];
        delete moderators[moderators.length - 1];
        moderators.length--;

        break;
      }
    }

  }

  function getModeratorCount() public view returns (uint)
  {
    return moderators.length;
  }
  
  function isModerator(address addr) public view returns (bool)
  {
    for(uint i = 0; i < moderators.length; i++)
    {
      if(addr == moderators[i])
      {
        return true;
      }
    }

    return false;
  }

}
