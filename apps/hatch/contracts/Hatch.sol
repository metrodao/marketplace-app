pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/common/EtherTokenConstant.sol";
import "@aragon/os/contracts/common/IsContract.sol";
import "@aragon/os/contracts/common/SafeERC20.sol";
import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/lib/math/SafeMath64.sol";
import "@aragon/os/contracts/lib/token/ERC20.sol";
import "@aragon/apps-token-manager/contracts/TokenManager.sol";
import "@1hive/apps-marketplace-shared-interfaces/contracts/IHatch.sol";
import "@1hive/apps-marketplace-shared-interfaces/contracts/IMarketplaceController.sol";


contract Hatch is IHatch, EtherTokenConstant, IsContract, AragonApp {
    using SafeERC20  for ERC20;
    using SafeMath   for uint256;
    using SafeMath64 for uint64;

    /**
    Hardcoded constants to save gas
    bytes32 public constant OPEN_ROLE       = keccak256("OPEN_ROLE");
    bytes32 public constant CONTRIBUTE_ROLE = keccak256("CONTRIBUTE_ROLE");
    */
    bytes32 public constant OPEN_ROLE       = 0xefa06053e2ca99a43c97c4a4f3d8a394ee3323a8ff237e625fba09fe30ceb0a4;
    bytes32 public constant CONTRIBUTE_ROLE = 0x9ccaca4edf2127f20c425fdd86af1ba178b9e5bee280cd70d88ac5f6874c4f07;

    uint256 public constant PPM = 1000000; // 0% = 0 * 10 ** 4; 1% = 1 * 10 ** 4; 100% = 100 * 10 ** 4

    string private constant ERROR_CONTRACT_IS_EOA          = "HATCH_CONTRACT_IS_EOA";
    string private constant ERROR_INVALID_BENEFICIARY      = "HATCH_INVALID_BENEFICIARY";
    string private constant ERROR_INVALID_CONTRIBUTE_TOKEN = "HATCH_INVALID_CONTRIBUTE_TOKEN";
    string private constant ERROR_INVALID_MIN_GOAL         = "HATCH_INVALID_MIN_GOAL";
    string private constant ERROR_INVALID_MAX_GOAL         = "HATCH_INVALID_MAX_GOAL";
    string private constant ERROR_INVALID_EXCHANGE_RATE    = "HATCH_INVALID_EXCHANGE_RATE";
    string private constant ERROR_INVALID_TIME_PERIOD      = "HATCH_INVALID_TIME_PERIOD";
    string private constant ERROR_INVALID_PCT              = "HATCH_INVALID_PCT";
    string private constant ERROR_INVALID_STATE            = "HATCH_INVALID_STATE";
    string private constant ERROR_INVALID_CONTRIBUTE_VALUE = "HATCH_INVALID_CONTRIBUTE_VALUE";
    string private constant ERROR_INSUFFICIENT_BALANCE     = "HATCH_INSUFFICIENT_BALANCE";
    string private constant ERROR_INSUFFICIENT_ALLOWANCE   = "HATCH_INSUFFICIENT_ALLOWANCE";
    string private constant ERROR_NOTHING_TO_REFUND        = "HATCH_NOTHING_TO_REFUND";
    string private constant ERROR_TOKEN_TRANSFER_REVERTED  = "HATCH_TOKEN_TRANSFER_REVERTED";

    enum State {
        Pending,     // hatch is idle and pending to be started
        Funding,     // hatch has started and contributors can purchase tokens
        Refunding,   // hatch has not reached min goal within period and contributors can claim refunds
        GoalReached, // hatch has reached min goal within period and trading is ready to be open
        Closed       // hatch has reached min goal within period, has been closed and trading has been open
    }

    IMarketplaceController                          public controller;
    TokenManager                                    public tokenManager;
    ERC20                                           public token;
    address                                         public reserve;
    address                                         public beneficiary;
    address                                         public contributionToken;

    uint256                                         public maxGoal;
    uint256                                         public minGoal;
    uint64                                          public period;
    uint256                                         public exchangeRate;
    uint64                                          public vestingCliffPeriod;
    uint64                                          public vestingCompletePeriod;
    uint256                                         public supplyOfferedPct;
    uint256                                         public fundingForBeneficiaryPct;
    uint64                                          public openDate;

    bool                                            public isClosed;
    uint64                                          public vestingCliffDate;
    uint64                                          public vestingCompleteDate;
    uint256                                         public totalRaised;
    mapping(address => mapping(uint256 => uint256)) public contributions; // contributor => (vestedPurchaseId => tokensSpent)

    event SetOpenDate (uint64 date);
    event Close       ();
    event Contribute  (address indexed contributor, uint256 value, uint256 amount, uint256 vestedPurchaseId);
    event Refund      (address indexed contributor, uint256 value, uint256 amount, uint256 vestedPurchaseId);


    /***** external function *****/

    /**
     * @notice Initialize hatch
     * @param _controller               The address of the controller contract
     * @param _tokenManager             The address of the [bonded] token manager contract
     * @param _reserve                  The address of the reserve [pool] contract
     * @param _beneficiary              The address of the beneficiary [to whom a percentage of the raised funds is be to be sent]
     * @param _contributionToken        The address of the token to be used to contribute
     * @param _maxGoal                  The max goal to be reached by the end of that hatch [in contribution token wei]
     * @param _minGoal                  The min goal to be reached by the end of that hatch [in contribution token wei]
     * @param _period                   The period within which to accept contribution for that hatch
     * @param _exchangeRate             The exchangeRate [= 1/price] at which [bonded] tokens are to be purchased for that hatch [in PPM]
     * @param _vestingCliffPeriod       The period during which purchased [bonded] tokens are to be cliffed
     * @param _vestingCompletePeriod    The complete period during which purchased [bonded] tokens are to be vested
     * @param _supplyOfferedPct         The percentage of the initial supply of [bonded] tokens to be offered during that hatch [in PPM]
     * @param _fundingForBeneficiaryPct The percentage of the raised contribution tokens to be sent to the beneficiary [instead of the fundraising reserve] when that hatch is closed [in PPM]
     * @param _openDate                 The date upon which that hatch is to be open [ignored if 0]
    */
    function initialize(
        IMarketplaceController       _controller,
        TokenManager                 _tokenManager,
        address                      _reserve,
        address                      _beneficiary,
        address                      _contributionToken,
        uint256                      _maxGoal,
        uint256                      _minGoal,
        uint64                       _period,
        uint256                      _exchangeRate,
        uint64                       _vestingCliffPeriod,
        uint64                       _vestingCompletePeriod,
        uint256                      _supplyOfferedPct,
        uint256                      _fundingForBeneficiaryPct,
        uint64                       _openDate
    )
        external
        onlyInit
    {
        require(isContract(_controller),                                            ERROR_CONTRACT_IS_EOA);
        require(isContract(_tokenManager),                                          ERROR_CONTRACT_IS_EOA);
        require(isContract(_reserve),                                               ERROR_CONTRACT_IS_EOA);
        require(_beneficiary != address(0),                                         ERROR_INVALID_BENEFICIARY);
        require(isContract(_contributionToken) || _contributionToken == ETH,        ERROR_INVALID_CONTRIBUTE_TOKEN);
        require(_minGoal > 0,                                                       ERROR_INVALID_MIN_GOAL);
        require(_maxGoal >= _minGoal,                                               ERROR_INVALID_MAX_GOAL);
        require(_period > 0,                                                        ERROR_INVALID_TIME_PERIOD);
        require(_exchangeRate > 0,                                                  ERROR_INVALID_EXCHANGE_RATE);
        require(_vestingCliffPeriod > _period,                                      ERROR_INVALID_TIME_PERIOD);
        require(_vestingCompletePeriod > _vestingCliffPeriod,                       ERROR_INVALID_TIME_PERIOD);
        require(_supplyOfferedPct > 0 && _supplyOfferedPct <= PPM,                  ERROR_INVALID_PCT);
        require(_fundingForBeneficiaryPct >= 0 && _fundingForBeneficiaryPct <= PPM, ERROR_INVALID_PCT);

        initialized();

        controller = _controller;
        tokenManager = _tokenManager;
        token = ERC20(_tokenManager.token());
        reserve = _reserve;
        beneficiary = _beneficiary;
        contributionToken = _contributionToken;
        maxGoal = _maxGoal;
        minGoal = _minGoal;
        period = _period;
        exchangeRate = _exchangeRate;
        vestingCliffPeriod = _vestingCliffPeriod;
        vestingCompletePeriod = _vestingCompletePeriod;
        supplyOfferedPct = _supplyOfferedPct;
        fundingForBeneficiaryPct = _fundingForBeneficiaryPct;

        if (_openDate != 0) {
            _setOpenDate(_openDate);
        }
    }

    /**
     * @notice Open hatch [enabling users to contribute]
    */
    function open() external auth(OPEN_ROLE) {
        require(state() == State.Pending, ERROR_INVALID_STATE);
        require(openDate == 0,            ERROR_INVALID_STATE);

        _open();
    }

    /**
     * @notice Contribute to the hatch up to `@tokenAmount(self.contributionToken(): address, _value)`
     * @param _contributor The address of the contributor
     * @param _value       The amount of contribution token to be spent
    */
    function contribute(address _contributor, uint256 _value) external payable nonReentrant auth(CONTRIBUTE_ROLE) {
        require(state() == State.Funding, ERROR_INVALID_STATE);
        require(_value != 0,              ERROR_INVALID_CONTRIBUTE_VALUE);

        if (contributionToken == ETH) {
            require(msg.value == _value, ERROR_INVALID_CONTRIBUTE_VALUE);
        } else {
            require(msg.value == 0,      ERROR_INVALID_CONTRIBUTE_VALUE);
        }

        _contribute(_contributor, _value);
    }

    /**
     * @notice Refund `_contributor`'s hatch contribution #`_vestedPurchaseId`
     * @param _contributor      The address of the contributor whose hatch contribution is to be refunded
     * @param _vestedPurchaseId The id of the contribution to be refunded
    */
    function refund(address _contributor, uint256 _vestedPurchaseId) external nonReentrant isInitialized {
        require(state() == State.Refunding, ERROR_INVALID_STATE);

        _refund(_contributor, _vestedPurchaseId);
    }

    /**
     * @notice Close hatch and open trading
    */
    function close() external nonReentrant isInitialized {
        require(state() == State.GoalReached, ERROR_INVALID_STATE);

        _close();
    }

    /***** public view functions *****/

    /**
     * @notice Computes the amount of [bonded] tokens that would be purchased for `@tokenAmount(self.contributionToken(): address, _value)`
     * @param _value The amount of contribution tokens to be used in that computation
    */
    function contributionToTokens(uint256 _value) public view isInitialized returns (uint256) {
        return _value.mul(exchangeRate).div(PPM);
    }

    function contributionToken() public view isInitialized returns (address) {
        return contributionToken;
    }

    /**
     * @notice Returns the current state of that hatch
    */
    function state() public view isInitialized returns (State) {
        if (openDate == 0 || openDate > getTimestamp64()) {
            return State.Pending;
        }

        if (totalRaised >= maxGoal) {
            if (isClosed) {
                return State.Closed;
            } else {
                return State.GoalReached;
            }
        }

        if (_timeSinceOpen() < period) {
            return State.Funding;
        } else if (totalRaised >= minGoal) {
            if (isClosed) {
                return State.Closed;
            } else {
                return State.GoalReached;
            }
        } else {
            return State.Refunding;
        }
    }

    /***** internal functions *****/

    function _timeSinceOpen() internal view returns (uint64) {
        if (openDate == 0) {
            return 0;
        } else {
            return getTimestamp64().sub(openDate);
        }
    }

    function _setOpenDate(uint64 _date) internal {
        require(_date >= getTimestamp64(), ERROR_INVALID_TIME_PERIOD);

        openDate = _date;
        _setVestingDatesWhenOpenDateIsKnown();

        emit SetOpenDate(_date);
    }

    function _setVestingDatesWhenOpenDateIsKnown() internal {
        vestingCliffDate = openDate.add(vestingCliffPeriod);
        vestingCompleteDate = openDate.add(vestingCompletePeriod);
    }

    function _open() internal {
        _setOpenDate(getTimestamp64());
    }

    function _contribute(address _contributor, uint256 _value) internal {
        uint256 value = totalRaised.add(_value) > maxGoal ? maxGoal.sub(totalRaised) : _value;
        if (contributionToken == ETH && _value > value) {
            msg.sender.transfer(_value.sub(value));
        }

        // (contributor) ~~~> contribution tokens ~~~> (hatch)
        if (contributionToken != ETH) {
            require(ERC20(contributionToken).balanceOf(_contributor) >= value,                ERROR_INSUFFICIENT_BALANCE);
            require(ERC20(contributionToken).allowance(_contributor, address(this)) >= value, ERROR_INSUFFICIENT_ALLOWANCE);
            _transfer(contributionToken, _contributor, address(this), value);
        }
        // (mint ???) ~~~> project tokens ~~~> (contributor)
        uint256 tokensToSell = contributionToTokens(value);
        tokenManager.issue(tokensToSell);
        uint256 vestedPurchaseId = tokenManager.assignVested(
            _contributor,
            tokensToSell,
            openDate,
            vestingCliffDate,
            vestingCompleteDate,
            true /* revokable */
        );
        totalRaised = totalRaised.add(value);
        // register contribution tokens spent in this purchase for a possible upcoming refund
        contributions[_contributor][vestedPurchaseId] = value;

        emit Contribute(_contributor, value, tokensToSell, vestedPurchaseId);
    }

    function _refund(address _contributor, uint256 _vestedPurchaseId) internal {
        // recall how much contribution tokens are to be refund for this purchase
        uint256 tokensToRefund = contributions[_contributor][_vestedPurchaseId];
        require(tokensToRefund > 0, ERROR_NOTHING_TO_REFUND);
        contributions[_contributor][_vestedPurchaseId] = 0;
        // (hatch) ~~~> contribution tokens ~~~> (contributor)
        _transfer(contributionToken, address(this), _contributor, tokensToRefund);
        /**
         * NOTE
         * the following lines assume that _contributor has not transfered any of its vested tokens
         * for now TokenManager does not handle switching the transferrable status of its underlying token
         * there is thus no way to enforce non-transferrability during the hatch phase only
         * this will be updated in a later version
        */
        // (contributor) ~~~> project tokens ~~~> (token manager)
        (uint256 tokensSold,,,,) = tokenManager.getVesting(_contributor, _vestedPurchaseId);
        tokenManager.revokeVesting(_contributor, _vestedPurchaseId);
        // (token manager) ~~~> project tokens ~~~> (burn ????)
        tokenManager.burn(address(tokenManager), tokensSold);

        emit Refund(_contributor, tokensToRefund, tokensSold, _vestedPurchaseId);
    }

    function _close() internal {
        isClosed = true;

        // (hatch) ~~~> contribution tokens ~~~> (beneficiary)
        uint256 fundsForBeneficiary = totalRaised.mul(fundingForBeneficiaryPct).div(PPM);
        if (fundsForBeneficiary > 0) {
            _transfer(contributionToken, address(this), beneficiary, fundsForBeneficiary);
        }
        // (hatch) ~~~> contribution tokens ~~~> (reserve)
        uint256 tokensForReserve = contributionToken == ETH ? address(this).balance : ERC20(contributionToken).balanceOf(address(this));

        _transfer(contributionToken, address(this), reserve, tokensForReserve);
        // (mint ???) ~~~> project tokens ~~~> (beneficiary)
        uint256 tokensForBeneficiary = token.totalSupply().mul(PPM.sub(supplyOfferedPct)).div(supplyOfferedPct);
        tokenManager.issue(tokensForBeneficiary);
        tokenManager.assignVested(
            beneficiary,
            tokensForBeneficiary,
            openDate,
            vestingCliffDate,
            vestingCompleteDate,
            false /* revokable */
        );
        // open trading
        controller.openTrading();

        emit Close();
    }

    function _transfer(address _token, address _from, address _to, uint256 _amount) internal {
        if (_token == ETH) {
            require(_from == address(this), ERROR_TOKEN_TRANSFER_REVERTED);
            require(_to != address(this),   ERROR_TOKEN_TRANSFER_REVERTED);
            _to.transfer(_amount);
        } else {
            if (_from == address(this)) {
                require(ERC20(_token).safeTransfer(_to, _amount), ERROR_TOKEN_TRANSFER_REVERTED);
            } else {
                require(ERC20(_token).safeTransferFrom(_from, _to, _amount), ERROR_TOKEN_TRANSFER_REVERTED);
            }
        }
    }
}
