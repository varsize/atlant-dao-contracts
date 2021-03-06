pragma solidity ^0.4.11;

import "./Owned.sol";
import "./PropertyPlatform.sol";

/* The shareholder association contract itself */
contract Association is owned, PropertyPlatform {

    /* Contract Variables and events */
    uint public minimumQuorum;
    uint public debatingPeriodInMinutes;
    Proposal[] public proposals;
    uint public numProposals;
    ERC20 public sharesTokenAddress;
		uint public percentFee;
		mapping(address => bool) public ptoBeneficiaries;

    event ProposalAdded(uint proposalID, uint proposedFee, string description);
    event Voted(uint proposalID, bool position, address voter);
    event ProposalTallied(uint proposalID, uint result, uint quorum, bool active);
    event ChangeOfRules(uint newMinimumQuorum, uint newDebatingPeriodInMinutes);
		event AddPropertyBeneficiary(address beneficiaryAddress);

    struct Proposal {
			uint proposedFee;
      string description;
      uint votingDeadline;
      bool executed;
      bool proposalPassed;
      uint numberOfVotes;
      bytes32 proposalHash;
      Vote[] votes;
      mapping (address => bool) voted;
    }

    struct Vote {
      bool inSupport;
      address voter;
    }

    /* modifier that allows only shareholders to vote and create new proposals */
    modifier onlyShareholders {
        require (sharesTokenAddress.balanceOf(msg.sender) > 0);
        _;
    }

    /* First time setup */
    function Association(address sharesAddress, uint minimumSharesToPassAVote, uint minutesForDebate, uint defaultPercentFee, string lawyerName, uint lawyerFee, address lawyerAddress) PropertyPlatform(lawyerName, lawyerFee, lawyerAddress) {
				percentFee = defaultPercentFee;
				sharesTokenAddress = ERC20(sharesAddress);
				changeVotingRules(minimumSharesToPassAVote, minutesForDebate);
    }

    function changeVotingRules(uint minimumSharesToPassAVote, uint minutesForDebate) onlyOwner {
        if (minimumSharesToPassAVote == 0 ) minimumSharesToPassAVote = 1;
        minimumQuorum = minimumSharesToPassAVote;
        debatingPeriodInMinutes = minutesForDebate;
        ChangeOfRules(minimumQuorum, debatingPeriodInMinutes);
    }

    function newFeeProposal(uint proposedFee, string JobDescription, bytes transactionBytecode) onlyShareholders
        returns (uint proposalID)
    {
        proposalID = proposals.length++;
        Proposal storage p = proposals[proposalID];
				p.proposedFee = proposedFee;
        p.description = JobDescription;
        p.proposalHash = sha3(proposedFee, transactionBytecode);

        p.votingDeadline = now + debatingPeriodInMinutes * 1 minutes;
        p.executed = false;
        p.proposalPassed = false;
        p.numberOfVotes = 0;
        ProposalAdded(proposalID, proposedFee, JobDescription);

        numProposals = proposalID + 1;

        return proposalID;
    }

    /* function to check if a proposal code matches */
    function checkProposalCode(uint proposalNumber, uint proposedFee, bytes transactionBytecode) constant
        returns (bool codeChecksOut)
    {
        Proposal storage p = proposals[proposalNumber];
        return p.proposalHash == sha3(proposedFee, transactionBytecode);
    }

    /* */
    function vote(uint proposalNumber, bool supportsProposal) onlyShareholders returns (uint voteID) {
        Proposal storage p = proposals[proposalNumber];
        require (p.voted[msg.sender] != true);

        voteID = p.votes.length++;
        p.votes[voteID] = Vote({inSupport: supportsProposal, voter: msg.sender});
        p.voted[msg.sender] = true;
        p.numberOfVotes = voteID +1;
        Voted(proposalNumber,  supportsProposal, msg.sender);
        return voteID;
    }

    function executeProposal(uint proposalNumber, bytes transactionBytecode) {
        Proposal storage p = proposals[proposalNumber];
        /* Check if the proposal can be executed */
        require (now >= p.votingDeadline  /* has the voting deadline passed? */
            && !p.executed        /* has it been already executed? */
            &&  p.proposalHash == sha3(p.proposedFee, transactionBytecode)); /* Does the transaction code match the proposal? */


        /* tally the votes */
        uint quorum = 0;
        uint yea = 0;
        uint nay = 0;

        for (uint i = 0; i <  p.votes.length; ++i) {
            Vote storage v = p.votes[i];
            uint voteWeight = sharesTokenAddress.balanceOf(v.voter);
            quorum += voteWeight;
            if (v.inSupport) {
                yea += voteWeight;
            } else {
                nay += voteWeight;
            }
        }

        /* execute result */
        require (quorum >= minimumQuorum); /* Not enough significant voters */

        if (yea > nay ) {
            /* has quorum and was approved */
            p.executed = true;
            percentFee = p.proposedFee;
            p.proposalPassed = true;
        } else {
            p.proposalPassed = false;
        }
        // Fire Events
        ProposalTallied(proposalNumber, yea - nay, quorum, p.proposalPassed);
    }

		function launchPropertySale(uint propertyID) external{
			super.launchPTO(sharesTokenAddress, propertyID, percentFee, this);
		}

		function addSelfToBeneficiaries() {
			require(sharesTokenAddress.balanceOf(msg.sender) > 0);
			if (!ptoBeneficiaries[msg.sender]) { //check if address is already eligible for receiving property tokens
				AddPropertyBeneficiary(msg.sender);
				ptoBeneficiaries[msg.sender] = true;
			}
		}
}
