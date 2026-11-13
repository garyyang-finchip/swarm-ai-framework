// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IEligibility} from "../interfaces/IEligibility.sol";
import {IERC8004Identity} from "./interfaces/IERC8004Identity.sol";

/// @title  ERC8004Eligibility — a member must be a registered agent (reference v0.3)
/// @notice An account declares the agent it acts for; the declaration is accepted only if the
///         account is the agent's owner or its agent wallet at that moment. `isEligible` re-reads
///         the same predicate live, so a transfer of the agent or a change of its wallet makes a
///         later `challenge` suspend the member. The module stores no claim about trust: it binds
///         a seat to an identity and nothing more. Compose it with assertion or state modules for
///         trust conditions.
/// @dev    v0.3: a declaration is a flag of its own, not the value of the agent id. ERC-8004
///         registries number agents from 0 (the reference implementation's `_lastId++`; Agent #0
///         exists on the official Sepolia deployment), and v0.2 used `agentId == 0` as "no
///         declaration" in both `declareAgent` and `isEligible`, so the first agent of any
///         registry could never hold a seat. `agentOf` keeps its v0.2 signature and its full
///         `uint256` range (an id is whatever the registry issued; nothing here narrows it);
///         `declared` says whether the id it returns is a declaration. A module must tell an
///         undeclared account from a legitimate agent id 0.
contract ERC8004Eligibility is IEligibility {
    IERC8004Identity public immutable identity;

    /// @notice The agent an account declared; 0 when it declared none, and also when it declared
    ///         agent 0 — read `declared` to tell the two apart.
    mapping(address => uint256) public agentOf;

    /// @notice Whether the account has declared an agent.
    mapping(address => bool) public declared;

    event AgentDeclared(address indexed account, uint256 indexed agentId);

    constructor(IERC8004Identity identity_) {
        require(address(identity_) != address(0), "ERC8004Eligibility: zero registry");
        identity = identity_;
    }

    /// @notice Declare the agent this account acts for. Any id the registry knows is accepted,
    ///         agent 0 included; the account must be the agent's owner or its agent wallet now.
    function declareAgent(uint256 agentId) external {
        require(_controls(msg.sender, agentId), "ERC8004Eligibility: not the agent's owner or wallet");
        agentOf[msg.sender] = agentId;
        declared[msg.sender] = true;
        emit AgentDeclared(msg.sender, agentId);
    }

    function isEligible(bytes32, bytes32, address account) external view returns (bool) {
        return declared[account] && _controls(account, agentOf[account]);
    }

    function _controls(address account, uint256 agentId) private view returns (bool) {
        (bool ok, bytes memory ret) = address(identity).staticcall(abi.encodeWithSelector(IERC8004Identity.ownerOf.selector, agentId));
        if (!ok || ret.length != 32) return false;
        if (abi.decode(ret, (address)) == account) return true;
        (ok, ret) = address(identity).staticcall(abi.encodeWithSelector(IERC8004Identity.getAgentWallet.selector, agentId));
        return ok && ret.length == 32 && abi.decode(ret, (address)) == account;
    }
}
