pragma solidity ^0.4.18;

import "./MintableToken.sol";
import "./oraclizeAPI.sol";

//For production, change all days to days
//Change and check days and discounts
contract Mindmap_Token is Ownable, usingOraclize {
    using SafeMath for uint256;

    // The token being sold
    MintableToken public token;

    // start and end timestamps where investments are allowed (both inclusive)
    uint256 public PrivateSaleStartTime;
    uint256 public PrivateSaleEndTime;
    uint256 public PrivateSaleCents = 20;
    uint256 public PrivateSaleDays = 28;

    uint256 public PreICOStartTime;
    uint256 public PreICOEndTime;
    uint256 public PreICODayOneCents = 25;
    uint256 public PreICOCents = 30;
    uint256 public PreICODays = 31;
    uint256 public PreICOEarlyDays = 1;
    
    uint256 public ICOStartTime;
    uint256 public ICOEndTime;
    uint256 public ICOCents = 40;
    uint256 public ICODays = 60;

    uint256 public DefaultCents = 50;

    uint256 public FirstEtherLimit = 5;
    uint256 public FirstBonus = 120;
    uint256 public SecondEtherLimit = 10;
    uint256 public SecondBonus = 125;
    uint256 public ThirdEtherLimit = 15;
    uint256 public ThirdBonus = 135;
    
    uint256 public hardCap = 140000000;
    uint256 public purchased = 0;
    uint256 public gifted = 0;

    // address where funds are collected
    address public wallet;

    // how many token units a buyer gets per wei
    uint256 public rate;
    uint256 public weiRaised;

    /**
    * event for token purchase logging
    * @param purchaser who paid for the tokens
    * @param beneficiary who got the tokens
    * @param value weis paid for purchase
    * @param amount amount of tokens purchased
    */
    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);
    event newOraclizeQuery(string description);

    function Mindmap_Token(uint256 _rate, address _wallet) public {
        require(_rate > 0);
        require(_wallet != address(0));

        token = createTokenContract();

        rate = _rate;
        wallet = _wallet;
    }

    function startPrivateSale() onlyOwner public {
        PrivateSaleStartTime = now;
        PrivateSaleEndTime = PrivateSaleStartTime + PrivateSaleDays * 1 days;
    }
    function stopPrivateSale() onlyOwner public {
        PrivateSaleEndTime = now;
    }
    function startPreICO() onlyOwner public {
        PreICOStartTime = now;
        PreICOEndTime = PreICOStartTime + PreICODays * 1 days;
    }
    function stopPreICO() onlyOwner public {
        PreICOEndTime = now;
    }
    function startICO() onlyOwner public {
        ICOStartTime = now;
        ICOEndTime = ICOStartTime + ICODays * 1 days;
    }
    function stopICO() onlyOwner public {
        ICOEndTime = now;
    }

    // creates the token to be sold.
    // override this method to have crowdsale of a specific mintable token.
    function createTokenContract() internal returns (MintableToken) {
        return new MintableToken();
    }

    // fallback function can be used to buy tokens
    function () payable public {
        buyTokens(msg.sender);
    }

    //return token price in cents
    function getUSDPrice() public constant returns (uint256 cents_by_token) {
        if (PrivateSaleStartTime > 0 && PrivateSaleStartTime <= now && now < PrivateSaleEndTime ) 
        {
            return PrivateSaleCents;
        } 
        else if (PreICOStartTime > 0 && PreICOStartTime <= now && now < PreICOEndTime)
        {
            if (now < PreICOStartTime + PreICOEarlyDays * 1 days) 
                return PreICODayOneCents;
            else 
                return PreICOCents;
        }
        else if (ICOStartTime > 0 && ICOStartTime <= now && now < ICOEndTime)
        {
            return ICOCents;
        }
        else 
        {
            return DefaultCents;
        }
    }
    function calcBonus(uint256 tokens, uint256 ethers) public constant returns (uint256 tokens_with_bonus) {
        if (ethers >= ThirdEtherLimit)
            return tokens.mul(ThirdBonus).div(100);
        else if (ethers >= SecondEtherLimit)
            return tokens.mul(SecondBonus).div(100);
        else if (ethers >= FirstEtherLimit)
            return tokens.mul(FirstBonus).div(100);
        else
            return tokens;
    }
    // string 123.45 to 12345 converter
    function stringFloatToUnsigned(string _s) payable returns (string) {
        bytes memory _new_s = new bytes(bytes(_s).length - 1);
        uint k = 0;

        for (uint i = 0; i < bytes(_s).length; i++) {
            if (bytes(_s)[i] == '.') { break; } // 1

            _new_s[k] = bytes(_s)[i];
            k++;
        }

        return string(_new_s);
    }
    // callback for oraclize 
    function __callback(bytes32 myid, string result) {
         require(msg.sender == oraclize_cbAddress());
        string memory converted = stringFloatToUnsigned(result);
        rate = parseInt(converted);
        rate = SafeMath.div(1000000000000000000, rate); // price for 1 `usd` in `wei` 
    }
    // price updater 
    function updatePrice() payable {
        oraclize_setProof(proofType_NONE);
        if (oraclize_getPrice("URL") > this.balance) {
            newOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            newOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            oraclize_query("URL", "json(https://min-api.cryptocompare.com/data/price?fsym=ETH&tsyms=USD).USD");
        }
    }
    // low level token purchase function
    function buyTokens(address beneficiary) public payable {
        require(beneficiary != address(0));
        require(validPurchase());
        require(msg.value >= 50000000000000000);  // minimum contrib amount 0.05 ETH
        
        updatePrice();

        uint256 _convert_rate = SafeMath.div(SafeMath.mul(rate, getUSDPrice()), 100);

        // calculate token amount to be created
        uint256 weiAmount = SafeMath.mul(msg.value, 10**uint256(token.decimals()));
        uint256 tokens = SafeMath.div(weiAmount, _convert_rate);
        tokens = calcBonus(tokens, msg.value.div(10**uint256(token.decimals())));
        require(validTokenAmount(tokens));
        // update state
        purchased = SafeMath.add(purchased, tokens);
        weiRaised = SafeMath.add(weiRaised, msg.value);

        token.mint(beneficiary, tokens);
        TokenPurchase(msg.sender, beneficiary, msg.value, tokens);

        forwardFunds();
    }

    //to set ico sale values if needed
    function setSaleLength(uint256 private_in_days, uint256 preico_early_days, uint256 preico_in_days, uint256 ico_in_days)
    onlyOwner public {
        PrivateSaleDays = private_in_days;
        PreICOEarlyDays = preico_early_days;
        PreICODays = preico_in_days;
        ICODays = ico_in_days;
        if(PrivateSaleEndTime != 0)
            PrivateSaleEndTime = PrivateSaleStartTime + PrivateSaleDays * 1 days;
        if(PreICOEndTime != 0)
            PreICOEndTime = PreICOStartTime + PreICODays * 1 days;
        if(ICOEndTime != 0)
            ICOEndTime = ICOStartTime + ICODays * 1 days;
    }

    function setDiscount(uint256 private_in_cents, uint256 preicodayone_in_cents, uint256 preico_in_cents, uint256 ico_in_cents, uint256 default_in_cents) onlyOwner public {
        //values in USD cents
        PrivateSaleCents = private_in_cents;
        PreICODayOneCents = preicodayone_in_cents;
        PreICOCents = preico_in_cents;
        ICOCents = ico_in_cents;
        DefaultCents = default_in_cents;
    }
    
    function setBonus(uint256 first_ether_limit, uint256 first_bonus, uint256 second_ether_limit, uint256 second_bonus, uint256 third_ether_limit, uint256 third_bonus) onlyOwner public {
        //values in Ether and X%+100
        FirstEtherLimit = first_ether_limit;
        FirstBonus = first_bonus;
        SecondEtherLimit = second_ether_limit;
        SecondBonus = second_bonus;
        ThirdEtherLimit = third_ether_limit;
        ThirdBonus = third_bonus;
    }

   // Upgrade token functions
    function freezeToken() onlyOwner public {
        token.pause();
    }


    function unfreezeToken() onlyOwner public {
        token.unpause();
    }
    
    //to send tokens for bitcoin bakers and bounty
    function sendTokens(address _to, uint256 _amount) onlyOwner public {
        require(token.totalSupply() + SafeMath.mul(_amount, 10**uint256(token.decimals())) <= SafeMath.mul(hardCap, 10**uint256(token.decimals())));
        gifted =  SafeMath.add(gifted, SafeMath.mul(_amount, 10**uint256(token.decimals())));
        token.mint(_to, SafeMath.mul(_amount, 10**uint256(token.decimals())));
    }
    
    //change owner for child contract
    function transferTokenOwnership(address _newOwner) onlyOwner public {
        token.transferOwnership(_newOwner);
    }

    // send ether to the fund collection wallet
    // override to create custom fund forwarding mechanisms
    function forwardFunds() internal {
        wallet.transfer(this.balance);
    }
    
    function validTokenAmount(uint256 tokenAmount) internal constant returns (bool) {
        require(tokenAmount > 0);
        bool tokenAmountOk = token.totalSupply() - gifted + tokenAmount <= ( SafeMath.mul(SafeMath.div(SafeMath.mul(hardCap,70), 100), 10**uint256(token.decimals())));
        return tokenAmountOk;
    }

    // @return true if the transaction can buy tokens
    function validPurchase() internal constant returns (bool) {
        bool hardCapOk = token.totalSupply() - gifted <= ( SafeMath.mul(SafeMath.div(SafeMath.mul(hardCap,70), 100), 10**uint256(token.decimals())));
        bool withinPrivateSalePeriod = now >= PrivateSaleStartTime && now <= PrivateSaleEndTime;
        bool withinPreICOPeriod = now >= PreICOStartTime && now <= PreICOEndTime;
        bool withinICOPeriod = now >= ICOStartTime && now <= ICOEndTime;
        bool nonZeroPurchase = msg.value != 0;
        return hardCapOk && (withinPreICOPeriod || withinICOPeriod || withinPrivateSalePeriod) && nonZeroPurchase;
    }
}