// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title IDRXTransferManager
 * @dev Manages IDRX reserves and handles transfers to recipients
 * Token transfers from senders are handled off-chain/cross-chain by the platform
 */
contract IDRXTransferManager is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    address public idrxToken;

    uint256 public baseFee = 100;
    uint256 public dynamicFee = 50;
    uint256 public constant MAX_FEE = 500;

    uint256 public minTransferAmount = 10000;
    uint256 public maxTransferAmount = 10000000;

    // uint256 public currentReserve;
    uint256 public reserveThreshold = 1000000;
    uint256 public lowReserveMaxAmount = 100000;

    uint256 public emergencyThreshold = 100000;

    event IDRXTransferred(
        bytes32 indexed transferId,
        address indexed recipient,
        uint256 idrxAmount,
        uint256 feeAmount,
        uint256 timestamp
    );

    event ReserveReplenished(
        uint256 amount,
        uint256 newReserve,
        uint256 timestamp
    );
    event ReserveWithdrawn(
        uint256 amount,
        uint256 newReserve,
        uint256 timestamp
    );
    event FeeUpdated(uint256 baseFee, uint256 dynamicFee);
    event TransferLimitsUpdated(uint256 minAmount, uint256 maxAmount);
    event ReserveThresholdsUpdated(
        uint256 reserveThreshold,
        uint256 lowReserveMaxAmount,
        uint256 emergencyThreshold
    );

    /**
     * @dev Initializes the contract with the IDRX token address and initial settings
     * @param _idrxToken Address of the IDRX token
     */
    constructor(address _idrxToken) {
        require(_idrxToken != address(0), "Invalid IDRX token address");

        idrxToken = _idrxToken;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    /**
     * @dev Transfer IDRX from reserve to recipient
     * Called by operators after confirming receipt of cross-chain assets
     * @param _transferId Unique identifier for this transfer
     * @param _recipient Address to receive the IDRX
     * @param _idrxAmount Amount of IDRX to be sent (before fees)
     */
    function transferIDRX(
        bytes32 _transferId,
        address _recipient,
        uint256 _idrxAmount
    ) external nonReentrant whenNotPaused onlyRole(OPERATOR_ROLE) {
        // Validate recipient's address
        require(_recipient != address(0), "Invalid recipient");
        
        // Validate user transfer amount against minimum transfer amount
        require(
            _idrxAmount >= minTransferAmount,
            "Below minimum transfer amount"
        );

        // Validate user transfer amount against maximum transfer amount
        uint256 effectiveMaxAmount = getEffectiveMaxTransferAmount();
        require(
            _idrxAmount <= effectiveMaxAmount,
            "Exceeds maximum transfer amount"
        );

        // Validate current idrx reserve in SC wallet
        uint256 currentReserve = getCurrentReserveAmount();
        require(_idrxAmount <= currentReserve, "Insufficient reserve");

        uint256 totalFee = calculateFee(_idrxAmount);
        uint256 recipientAmount = _idrxAmount - totalFee;
        
        // TODO: can be removed since reserveAmount will be automatically reduced as we call .transfer()
        // currentReserve -= _idrxAmount;

        // Send idrx to recipient
        require(
            IERC20(idrxToken).transfer(_recipient, recipientAmount),
            "IDRX transfer failed"
        );

        if (currentReserve < emergencyThreshold) {
            _pause();
        }

        emit IDRXTransferred(
            _transferId,
            _recipient,
            recipientAmount,
            totalFee,
            block.timestamp
        );
    }

    /**
     * @dev Add IDRX to the reserve
     * @param _amount Amount of IDRX to add
     */
    function replenishReserve(
        uint256 _amount
    ) external nonReentrant onlyRole(OPERATOR_ROLE) {
        require(_amount > 0, "Amount must be positive");

        require(
            IERC20(idrxToken).transferFrom(msg.sender, address(this), _amount),
            "IDRX transfer failed"
        );

        // TODO: can be removed since reserve amount will be added as .transferFrom() gets executed successfully (?)
        // currentReserve += _amount;

        uint256 currentReserve = getCurrentReserveAmount();

        if (paused() && currentReserve >= emergencyThreshold) {
            _unpause();
        }

        emit ReserveReplenished(_amount, currentReserve, block.timestamp);
    }

    /**
     * @dev Withdraw IDRX from the reserve (for admin operations)
     * @param _amount Amount of IDRX to withdraw
     * @param _to Address to send the IDRX to
     */
    function withdrawReserve(
        uint256 _amount,
        address _to
    ) external nonReentrant onlyRole(ADMIN_ROLE) {
        require(_amount > 0, "Amount must be positive");
        require(_to != address(0), "Invalid recipient");

        uint256 currentReserve = getCurrentReserveAmount();
        require(_amount <= currentReserve, "Insufficient reserve");

        // TODO: can be removed since reserveAmount will be automatically reduced as we call .transfer()
        // currentReserve -= _amount;

        require(
            IERC20(idrxToken).transfer(_to, _amount),
            "IDRX transfer failed"
        );

        if (currentReserve < emergencyThreshold) {
            _pause();
        }

        emit ReserveWithdrawn(_amount, currentReserve, block.timestamp);
    }

    /**
     * @dev Update fee parameters
     * @param _baseFee New base fee in basis points
     * @param _dynamicFee New dynamic fee in basis points
     */
    function updateFees(
        uint256 _baseFee,
        uint256 _dynamicFee
    ) external onlyRole(ADMIN_ROLE) {
        require(_baseFee + _dynamicFee <= MAX_FEE, "Total fee exceeds maximum");

        baseFee = _baseFee;
        dynamicFee = _dynamicFee;

        emit FeeUpdated(_baseFee, _dynamicFee);
    }

    /**
     * @dev Update transfer limits
     * @param _minAmount New minimum transfer amount
     * @param _maxAmount New maximum transfer amount
     */
    function updateTransferLimits(
        uint256 _minAmount,
        uint256 _maxAmount
    ) external onlyRole(ADMIN_ROLE) {
        require(_minAmount > 0, "Minimum amount must be positive");
        require(_maxAmount >= _minAmount, "Invalid range");

        minTransferAmount = _minAmount;
        maxTransferAmount = _maxAmount;

        emit TransferLimitsUpdated(_minAmount, _maxAmount);
    }

    /**
     * @dev Update reserve thresholds
     * @param _reserveThreshold New reserve threshold for reducing max amount
     * @param _lowReserveMaxAmount New maximum amount when reserves are low
     * @param _emergencyThreshold New threshold for emergency shutdown
     */
    function updateReserveThresholds(
        uint256 _reserveThreshold,
        uint256 _lowReserveMaxAmount,
        uint256 _emergencyThreshold
    ) external onlyRole(ADMIN_ROLE) {
        require(
            _emergencyThreshold > 0,
            "Emergency threshold must be positive"
        );
        require(
            _reserveThreshold >= _emergencyThreshold,
            "Invalid threshold range"
        );
        require(
            _lowReserveMaxAmount <= maxTransferAmount,
            "Invalid max amount"
        );

        reserveThreshold = _reserveThreshold;
        lowReserveMaxAmount = _lowReserveMaxAmount;
        emergencyThreshold = _emergencyThreshold;

        emit ReserveThresholdsUpdated(
            _reserveThreshold,
            _lowReserveMaxAmount,
            _emergencyThreshold
        );
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        require(
            getCurrentReserveAmount() >= emergencyThreshold,
            "Reserve below emergency threshold"
        );
        _unpause();
    }

    /**
     * @dev Calculate the total fee for a transaction
     * @param _amount Amount of IDRX being transferred
     * @return Total fee amount
     */
    function calculateFee(uint256 _amount) public view returns (uint256) {
        uint256 baseAmount = (_amount * baseFee) / 10000;
        uint256 dynamicAmount = (_amount * dynamicFee) / 10000;
        return baseAmount + dynamicAmount;
    }

    /**
     * @dev Get the effective maximum transfer amount based on current reserves
     * @return The effective maximum amount
     */
    function getEffectiveMaxTransferAmount() public view returns (uint256) {
        uint256 currentReserve = getCurrentReserveAmount();

        if (currentReserve < reserveThreshold) {
            return lowReserveMaxAmount;
        }

        return maxTransferAmount;
    }

    /**
     * @dev Get current reserve and status information
     * @return reserve Current IDRX reserve
     * @return effectiveMaxAmount Current effective maximum transfer amount
     * @return isActive Whether the contract is active (not paused)
     */
    function getReserveStatus()
        external
        view
        returns (uint256 reserve, uint256 effectiveMaxAmount, bool isActive)
    {
        return (getCurrentReserveAmount(), getEffectiveMaxTransferAmount(), !paused());
    }

    // TODO: confirm about this function's use case
    // /**
    //  * @dev Recover any excess IDRX (beyond the tracked reserve)
    //  * @param _to Address to send the excess IDRX to
    //  */
    // function recoverExcessIDRX(
    //     address _to
    // ) external nonReentrant onlyRole(ADMIN_ROLE) {
    //     require(_to != address(0), "Invalid recipient");

    //     uint256 balance = IERC20(idrxToken).balanceOf(address(this));
    //     require(balance > currentReserve, "No excess IDRX to recover");

    //     uint256 excessAmount = balance - currentReserve;

    //     require(
    //         IERC20(idrxToken).transfer(_to, excessAmount),
    //         "IDRX transfer failed"
    //     );
    // }

    function getCurrentReserveAmount() public view returns (uint256) {
        return IERC20(idrxToken).balanceOf(address(this));
    }
}
