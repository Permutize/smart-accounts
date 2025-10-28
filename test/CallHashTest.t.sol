// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Permutize
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CallHash } from "../src/libraries/CallHash.sol";
import { IBaseAccount } from "../src/interfaces/IBaseAccount.sol";
import { BaseTest } from "../utils/test/BaseTest.sol";

contract CallHashTest is BaseTest {
    address constant USDC = 0x41a0D237f5882A05e7754CFB4a85B932f840CF7d;
    address constant FEE_MANAGER = 0x153C7ca54d937945D8f05BbeCb3EfEa453C692DC;

    function setUp() public { }

    // ============ Test Type Hash Constants ============

    function test_BatchHash() public pure {
        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](1);
        uint256 amount = 1000;
        calls[0] = IBaseAccount.Call({
            to: USDC, value: 0, data: abi.encodeWithSelector(IERC20.transfer.selector, FEE_MANAGER, amount)
        });
        IBaseAccount.Batch memory batch = IBaseAccount.Batch({ nonce: 0, deadline: 12_345, calls: calls });

        bytes32 h = CallHash.hash(batch);
        assertEq(h, hex"28f4aedad456586b4fda5cfaec7dc10a5762a8b4b6c4b269d61fe409df6105b6");
    }
}
