// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IDRXHL} from "src/IDRXHL.sol";

contract IDRXHLTest is Test {
    IDRXHL private token;
    address private admin;
    address private minter;
    address private user;

    function setUp() public {
        admin = address(1);
        minter = address(2);
        user = address(3);

        token = new IDRXHL(admin, minter);
    }

    function testInitialSupply() public view {
        uint256 expectedSupply = 10000000000000000000000000000 * 10 ** token.decimals();
        assertEq(token.totalSupply(), expectedSupply);
    }

    function testMinterCanMint() public {
        uint256 mintAmount = 1000 * 10 ** token.decimals();

        vm.prank(minter);
        token.mint(user, mintAmount);

        assertEq(token.balanceOf(user), mintAmount);
    }

    function testNonMinterCannotMint() public {
        uint256 mintAmount = 1000 * 10 ** token.decimals();

        vm.prank(user); // Simulasi user biasa tanpa role MINTER
        vm.expectRevert(); // Harus revert karena user gak punya MINTER_ROLE
        token.mint(user, mintAmount);
    }

    function testBurnToken() public {
        uint256 mintAmount = 5000 * 10 ** token.decimals();

        vm.prank(minter);
        token.mint(user, mintAmount);

        vm.prank(user);
        token.burn(mintAmount);

        assertEq(token.balanceOf(user), 0);
    }

    function testOnlyAdminHasAdminRole() public view {
        bool hasAdminRole = token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin);
        assertTrue(hasAdminRole);

        bool userHasAdminRole = token.hasRole(token.DEFAULT_ADMIN_ROLE(), user);
        assertFalse(userHasAdminRole);
    }

    function testDecimalsIs2() public view {
        assertEq(token.decimals(), 2);
    }
}
