pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";

import {Coordinator} from "src/Coordinator.sol";

contract Controller is Ownable {
    // ! Constants
    uint256 public constant NODE_STAKING_AMOUNT = 50000;
    uint256 public constant DISQUALIFIED_NODE_PENALTY_AMOUNT = 1000;
    uint256 public constant COORDINATOR_STATE_TRIGGER_REWARD = 100;
    uint256 public constant DEFAULT_MINIMUM_THRESHOLD = 3;
    uint256 public constant DEFAULT_NUMBER_OF_COMMITTERS = 3;
    uint256 public constant DEFAULT_DKG_PHASE_DURATION = 10;
    uint256 public constant GROUP_MAX_CAPACITY = 10;
    uint256 public constant IDEAL_NUMBER_OF_GROUPS = 5;
    uint256 public constant PENDING_BLOCK_AFTER_QUIT = 100;

    uint256 epoch = 0; // self.epoch, previously ined in adapter

    //  Node State Variables
    mapping(address => Node) public nodes; //maps node address to Node Struct
    mapping(address => uint256) public rewards; // maps node address to reward amount
    mapping(address => bool) public nodeRegistered; // map for checking if nodes are registered

    struct Node {
        address idAddress;
        bytes dkgPublicKey;
        bool state;
        uint256 pending_until_block;
        uint256 staking;
    }

    // Group State Variables
    uint256 public groupCount; // Number of groups
    mapping(uint256 => Group) public groups; // group_index => Group struct
    mapping(uint256 => bool) public groupRegistered; // map for checking if group exists

    struct Group {
        uint256 index; // group_index
        uint256 epoch; // 0
        uint256 size; // 0
        uint256 threshold; // DEFAULT_MINIMUM_THRESHOLD
        Member[] members;
    }

    struct Member {
        uint256 index;
        address nodeIdAddress;
        bytes partialPublicKey;
    }

    // ! Coordinator State Variables
    mapping(uint256 => address) public coordinators; // maps group index to coordinator address

    // ! Functions
    function nodeRegister(bytes calldata dkgPublicKey) public {
        require(!nodeRegistered[msg.sender], "Node is already registered"); // error sender already in list of nodes

        // TODO: Check to see if enough balance for staking

        // Populate Node struct and insert into nodes
        Node storage n = nodes[msg.sender];
        n.idAddress = msg.sender;
        n.dkgPublicKey = dkgPublicKey;
        n.state = true;
        n.pending_until_block = 0;
        n.staking = NODE_STAKING_AMOUNT;

        nodeRegistered[msg.sender] = true;
        rewards[msg.sender] = 0; // This can be removed
        nodeJoin(msg.sender);
    }

    function nodeJoin(address idAddress) private {
        // * get groupIndex from findOrCreateTargetGroup -> addGroup
        (uint256 groupIndex, bool needsRebalance) = findOrCreateTargetGroup();
        addToGroup(idAddress, groupIndex, true); // * add to group
            // TODO: Reblance Group: Implement later!
            // if (needsRebalance) {
            //     // reblanceGroup();
            // }
    }

    // function reblanceGroup(uint256 groupIndexA, uint256 groupIndexB) private {}

    function findOrCreateTargetGroup()
        private
        returns (
            uint256, //groupIndex
            bool // needsRebalance
        )
    {
        if (groupCount == 0) {
            uint256 groupIndex = addGroup();
            return (groupIndex, false);
        }
        return (1, false); // TODO: Need to implement index_of_min_size
    }

    function addGroup() private returns (uint256) {
        groupCount++; // * Ruoshan, why does this break if ++ moved to next line?
        Group storage g = groups[groupCount];
        groupRegistered[groupCount] = true;
        g.index = groupCount;
        g.size = 0;
        g.threshold = DEFAULT_MINIMUM_THRESHOLD;
        return groupCount;
    }

    function addToGroup(address idAddress, uint256 groupIndex, bool emitEventInstantly) private {
        // Get group from group index
        Group storage g = groups[groupIndex];

        // Add Member Struct to group at group index
        Member memory m;
        m.index = g.size;
        m.nodeIdAddress = idAddress;

        // insert (node id address - > member) into group.members
        g.members.push(m);
        g.size++;

        // assign group threshold
        uint256 minimum = minimumThreshold(g.size); // 51% of group size
        // max of 51% of group size and DEFAULT_MINIMUM_THRESHOLD
        g.threshold = minimum > DEFAULT_MINIMUM_THRESHOLD ? minimum : DEFAULT_MINIMUM_THRESHOLD;

        if ((g.size >= 3) && emitEventInstantly) {
            emitGroupEvent(groupIndex);
        }
    }

    function minimumThreshold(uint256 groupSize) private pure returns (uint256) {
        uint256 min = groupSize / 2 + 1;
        return min;
    }

    function emitGroupEvent(uint256 groupIndex) private {
        require(groupRegistered[groupIndex], "Group does not exist"); // group must exist

        epoch++; // increment adapter epoch

        Group storage g = groups[groupIndex];
        g.epoch++;

        // TODO: is_strictly_majority_consensus, commit_cache, commiters

        Coordinator coordinator;

        coordinator = new Coordinator(
            // g.epoch, // TODO: epoch isnt in coordinator constructor atm.
            g.threshold,
            DEFAULT_DKG_PHASE_DURATION
        );

        coordinators[groupIndex] = address(coordinator);
    }

    // * Public Test functions for testing private stuff.
    // * DELETE LATER
    function tNonexistantGroup(uint256 groupIndex) public {
        emitGroupEvent(groupIndex);
    }

    function tMinimumThreshold(uint256 groupSize) public pure returns (uint256) {
        return minimumThreshold(groupSize);
    }

    function getNode(address nodeAddress) public view returns (Node memory) {
        return nodes[nodeAddress];
    }

    function getGroup(uint256 groupIndex) public view returns (Group memory) {
        return groups[groupIndex];
    }

    function getMember(uint256 groupIndex, uint256 memberIndex) public view returns (Member memory) {
        return groups[groupIndex].members[memberIndex];
    }

    function getCoordinator(uint256 groupIndex) public view returns (address) {
        return coordinators[groupIndex];
    }
}
