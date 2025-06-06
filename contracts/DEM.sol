pragma solidity >=0.4.21 <0.6.0;

import "./token/ERC20/ERC20Capped.sol";
import './DMValues.sol';

contract DEM is ERC20Capped(10000000000000000000000)
{
  uint256 public totalDividends;

  struct Account {
    uint256 balance;
    uint256 lastDividends;
  }
  mapping (address => Account) accounts;

  address public dmValuesAddress;

  constructor(address founder, address _dmValues) public {

  	// founder holds all tokens at first
  	// dividends will be credited to a profit collector account
    mint(founder, 10000000000000000000000);
    dmValuesAddress = _dmValues;
    totalDividends = 0;
  }

  function getCentralEscrowAddress() public view returns (address){

    return DMValues(dmValuesAddress).centralEscrowAddress();

  }

  function getMarketPlaceAddress() public view returns (address){

    return DMValues(dmValuesAddress).DMAddress();

  }

  function mint(address account, uint256 amount) public onlyMinter returns (bool) {

    Account memory ac;
    ac.balance = amount;
    ac.lastDividends = totalDividends;
    accounts[account] = ac;

    return super.mint(account, amount);
  }

  function dividendBalanceOf(address account) public view returns (uint256) {

    uint256 balance = 0;    
  	uint256 demTotal = super.totalSupply();

    uint256 newDividends = totalDividends.sub(accounts[account].lastDividends);
    uint256 product = accounts[account].balance.mul(newDividends);

    if(demTotal > 0)
      balance = product.div(demTotal);

    return balance;
  }

  function claimDividend() public {
    
    sendDividendTo(msg.sender);

  }

  function sendDividendTo(address payable recipient) internal{

  	require(recipient != address(0));

    uint256 owing = dividendBalanceOf(recipient);
    
    if (owing > 0) {
      
		  address payable beneficial = recipient;
	  	if(recipient == DMValues(dmValuesAddress).DMAddress())
	  		beneficial = DMValues(dmValuesAddress).profitCollector();
      
      beneficial.transfer(owing);      
    }

    accounts[recipient].lastDividends = totalDividends;
    
  }

  function transferByMarket(address _from, address _to, uint256 _value) public onlyMinter
  {
  	_transfer(_from, _to, _value);
  }

  function _transfer(address _from, address _to, uint256 _value) internal {

    require(_to != address(0));
    require(_value <= accounts[_from].balance);
    require(accounts[_to].balance + _value >= accounts[_to].balance);

    // clear dividends of both parties before transfer
  	sendDividendTo(address(uint160(_from)));    
   	sendDividendTo(address(uint160(_to)));

    require(accounts[_to].lastDividends == accounts[_from].lastDividends);
    accounts[_from].balance = accounts[_from].balance.sub(_value);
    accounts[_to].balance = accounts[_to].balance.add(_value);

    super._transfer(_from, _to, _value);
  }

  // fallback function to handle profit credited from the market
  function () external payable {

    totalDividends = totalDividends.add(msg.value);

  }
}
