// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PaymentSplitter
 * @dev This contract allows to split Ether payments among a group of accounts. The sender does not need to be aware
 * that the Ether will be split in this way, since it is handled transparently by the contract.
 *
 * The split can be in equal parts or in any other arbitrary proportion. The way this is specified is by assigning each
 * account to a number of shares. Of all the Ether that this contract receives.
 *
 * There are two different configurations, one for Primary Sales and another one for Secondary sales
 *
 */
contract PaymentSplitter is Context, Ownable {
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.AddressSet;

  event PrimarySalePayeeAdded(address account, uint256 shares);
  event SecondarySalePayeeAdded(address account, uint256 shares);

  event PrimarySalePaymentReceived(address from, uint256 amount);
  event SecondarySalePaymentReceived(address from, uint256 amount);

  event PrimarySalePayeeRemoved(address account);
  event SecondarySalePayeeRemoved(address account);

  mapping(address => uint256) private _sharesPrimarySales;
  mapping(address => uint256) private _sharesSecondarySales;
  EnumerableSet.AddressSet private _payeesPrimarySales;
  EnumerableSet.AddressSet private _payeesSecondarySales;

  /**
   * @dev Creates an instance of `PaymentSplitter` where each account in `payeesPrimarySales` and `payeesSecondary sales`
   * is assigned the number of shares at the matching position in the `sharesPrimarySales` and sharesSecondarySales array.
   *
   * All addresses in `payeesPrimarySales` and `payeesSecondary` must be non-zero. Both arrays must have the same non-zero
   * length, and there must be no duplicates.
   */
  constructor(
    address[] memory payeesPrimarySales_,
    uint256[] memory sharesPrimarySales_,
    address[] memory payeesSecondarySales_,
    uint256[] memory sharesSecondarySales_
  ) payable {
    require(
      payeesPrimarySales_.length == sharesPrimarySales_.length &&
        payeesSecondarySales_.length == sharesSecondarySales_.length,
      "PaymentSplitter: payees and shares length mismatch"
    );
    require(
      payeesPrimarySales_.length > 0 && payeesSecondarySales_.length > 0,
      "PaymentSplitter: no payees"
    );

    for (uint256 i = 0; i < payeesPrimarySales_.length; i++) {
      _addPayeePrimarySales(payeesPrimarySales_[i], sharesPrimarySales_[i]);
    }

    for (uint256 i = 0; i < payeesSecondarySales_.length; i++) {
      _addPayeeSecondarySales(
        payeesSecondarySales_[i],
        sharesSecondarySales_[i]
      );
    }
  }

  function updatePrimarySalesRoyalties(
    address[] memory payeesToRemove,
    address[] memory payeesToAdd,
    uint256[] memory shares
  ) external onlyOwner {
    for (uint256 i = 0; i < payeesToRemove.length; i++) {
      _removePayeePrimarySales(payeesToRemove[i]);
    }

    for (uint256 i = 0; i < payeesToAdd.length; i++) {
      _addPayeePrimarySales(payeesToAdd[i], shares[i]);
    }
  }

  function updateSecondarySalesRoyalties(
    address[] memory payeesToRemove,
    address[] memory payeesToAdd,
    uint256[] memory shares
  ) external onlyOwner {
    for (uint256 i = 0; i < payeesToRemove.length; i++) {
      _removePayeeSecondarySales(payeesToRemove[i]);
    }

    for (uint256 i = 0; i < payeesToAdd.length; i++) {
      _addPayeeSecondarySales(payeesToAdd[i], shares[i]);
    }
  }

  /**
   * @dev The Ether received will be logged with {SecondarySalePaymentReceived} events. Note that these events are not fully
   * reliable: it's possible for a contract to receive Ether without triggering this function. This only affects the
   * reliability of the events, and not the actual splitting of Ether.
   *
   * To learn more about this see the Solidity documentation for
   * https://solidity.readthedocs.io/en/latest/contracts.html#fallback-function[fallback
   * functions].
   */
  receive() external payable virtual {
    _splitPayment(_payeesSecondarySales, _sharesSecondarySales);
    emit SecondarySalePaymentReceived(_msgSender(), msg.value);
  }

  /**
   * @dev The Ether received from Primary Sales, this method will be called directly from minter contract
   */
  function receiveFromPrimarySale() external payable returns (bool) {
    _splitPayment(_payeesPrimarySales, _sharesPrimarySales);
    emit PrimarySalePaymentReceived(_msgSender(), msg.value);
    return true;
  }

  /**
   * @dev Getter for the amount of shares held by an account for primary sales.
   */
  function sharesPrimarySales(address[] memory accounts)
    public
    view
    returns (uint256[] memory)
  {
    uint256[] memory _sharesArray = new uint256[](accounts.length);
    for (uint256 i = 0; i < accounts.length; i++) {
      _sharesArray[i] = _sharesPrimarySales[accounts[i]];
    }
    return _sharesArray;
  }

  /**
   * @dev Getter for the amount of shares held by an account for primary sales.
   */
  function sharesSecondarySales(address[] memory accounts)
    public
    view
    returns (uint256[] memory)
  {
    uint256[] memory _sharesArray = new uint256[](accounts.length);
    for (uint256 i = 0; i < accounts.length; i++) {
      _sharesArray[i] = _sharesSecondarySales[accounts[i]];
    }
    return _sharesArray;
  }

  /**
   * @dev Getter all payess for primary sales.
   */
  function payeePrimarySales() public view returns (address[] memory) {
    address[] memory _payeesPrimarySalesArray = new address[](
      _payeesPrimarySales.length()
    );

    for (uint256 i = 0; i < _payeesPrimarySales.length(); i++) {
      _payeesPrimarySalesArray[i] = _payeesPrimarySales.at(i);
    }

    return _payeesPrimarySalesArray;
  }

  /**
   * @dev Getter all payess for secondary sales.
   */
  function payeeSecondarySales() public view returns (address[] memory) {
    address[] memory _payeesSecondarySalesArray = new address[](
      _payeesSecondarySales.length()
    );

    for (uint256 i = 0; i < _payeesSecondarySales.length(); i++) {
      _payeesSecondarySalesArray[i] = _payeesSecondarySales.at(i);
    }

    return _payeesSecondarySalesArray;
  }

  function _splitPayment(
    EnumerableSet.AddressSet storage payees,
    mapping(address => uint256) storage shares
  ) internal {
    for (uint256 i = 0; i < payees.length(); i++) {
      uint256 payeeAmount = (msg.value * shares[payees.at(i)]) / 100;
      (bool paymentSucess, ) = payable(payees.at(i)).call{value: payeeAmount}(
        ""
      );
      require(paymentSucess, "Payment failed");
    }
  }

  /**
   * @dev Add a new primary sale payee to the contract.
   * @param account The address of the payee to add.
   * @param shares_ The number of shares owned by the payee.
   */
  function _addPayeePrimarySales(address account, uint256 shares_) private {
    require(
      account != address(0),
      "PaymentSplitter: account is the zero address"
    );
    require(shares_ > 0, "PaymentSplitter: shares are 0");
    require(
      _sharesPrimarySales[account] == 0,
      "PaymentSplitter: account already has shares on primary sales"
    );

    _payeesPrimarySales.add(account);
    _sharesPrimarySales[account] = shares_;
    emit PrimarySalePayeeAdded(account, shares_);
  }

  /**
   * @dev Remove a primary sale payee to the contract.
   * @param account The address of the payee to remove.
   */
  function _removePayeePrimarySales(address account) private {
    require(
      account != address(0),
      "PaymentSplitter: account is the zero address"
    );
    require(
      _sharesPrimarySales[account] > 0,
      "PaymentSplitter: account does not have shares on primary sales"
    );

    _payeesPrimarySales.remove(account);
    _sharesPrimarySales[account] = 0;
    emit PrimarySalePayeeRemoved(account);
  }

  /**
   * @dev Add a new primary sale payee to the contract.
   * @param account The address of the payee to add.
   * @param shares_ The number of shares owned by the payee.
   */
  function _addPayeeSecondarySales(address account, uint256 shares_) private {
    require(
      account != address(0),
      "PaymentSplitter: account is the zero address"
    );
    require(shares_ > 0, "PaymentSplitter: shares are 0");
    require(
      _sharesSecondarySales[account] == 0,
      "PaymentSplitter: account already has shares on secondary sales"
    );

    _payeesSecondarySales.add(account);
    _sharesSecondarySales[account] = shares_;
    emit SecondarySalePayeeAdded(account, shares_);
  }

  /**
   * @dev Remove a secondary sale payee to the contract.
   * @param account The address of the payee to remove.
   */
  function _removePayeeSecondarySales(address account) private {
    require(
      account != address(0),
      "PaymentSplitter: account is the zero address"
    );
    require(
      _sharesSecondarySales[account] > 0,
      "PaymentSplitter: account does not have shares on secondary sales"
    );

    _payeesSecondarySales.remove(account);
    _sharesSecondarySales[account] = 0;
    emit SecondarySalePayeeRemoved(account);
  }
}
