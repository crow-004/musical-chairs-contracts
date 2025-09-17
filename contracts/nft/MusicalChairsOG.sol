// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @dev Thrown when trying to mint more tokens than MAX_SUPPLY.
error MaxSupplyReached();
/// @dev Thrown when an airdrop would exceed MAX_SUPPLY.
error AirdropExceedsMaxSupply();
/**
 * @title MusicalChairsOG
 * @author crow
 * @notice An upgradeable ERC721 contract for the "Musical Chairs: OG Member" NFT collection.
 * This collection is limited to a total supply of 300 tokens, intended for the
 * earliest and most dedicated community members. All tokens share the same metadata.
 */
contract MusicalChairsOG is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /// @notice A counter to keep track of the next token ID to be minted.
    uint256 internal _tokenIdCounter;

    /// @notice The maximum number of OG Member NFTs that can ever be minted.
    uint256 public constant MAX_SUPPLY = 300;

    /// @notice The URI for the token metadata JSON file, shared by all tokens in the collection.
    string private _tokenMetadataURI;

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @notice Disables the constructor to allow for upgradeable deployment.
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract.
     * @param initialOwner The address that will become the owner of this contract.
     * @param metadataURI The IPFS URI for the single metadata JSON file (e.g., "ipfs://YOUR_METADATA_FILE_CID").
     */
    function initialize(
        address initialOwner,
        string memory metadataURI
    ) public initializer {
        __ERC721_init("Musical Chairs: OG Member", "MC_OG");
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        _tokenMetadataURI = metadataURI;
    }

    /**
     * @notice Returns the metadata URI for a given token ID. All tokens share the same URI.
     * @param tokenId The ID of the token.
     * @return The metadata URI string.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // To ensure the function reverts for nonexistent tokens as per the EIP-721 standard,
        // we call `ownerOf`. This function from the parent ERC721Upgradeable contract
        // will revert if the token with `tokenId` does not exist.
        ownerOf(tokenId);
        return _tokenMetadataURI;
    }

    /**
     * @notice Allows the owner to update the metadata URI for the entire collection.
     * @dev This is useful if you need to update the metadata location.
     * @param newURI The new metadata URI string.
     */
    function setTokenURI(string memory newURI) public onlyOwner {
        _tokenMetadataURI = newURI;
    }

    /**
     * @notice Mints a new OG NFT and assigns it to a recipient.
     * @dev Can only be called by the owner. Reverts if the MAX_SUPPLY has been reached.
     * @param to The address that will receive the minted NFT.
     */
    function safeMint(address to) public onlyOwner {
        uint256 tokenId = _tokenIdCounter;
        if (tokenId > MAX_SUPPLY - 1) revert MaxSupplyReached();
        ++_tokenIdCounter;
        _safeMint(to, tokenId);
    }

    /**
     * @notice Mints multiple OG NFTs and assigns them to a list of recipients.
     * @dev Can only be called by the owner. Reverts if minting would exceed MAX_SUPPLY.
     *      This is more gas-efficient for large airdrops than calling safeMint repeatedly.
     * @param recipients An array of addresses that will receive the minted NFTs.
     */
    function airdrop(address[] calldata recipients) public onlyOwner {
        uint256 currentSupply = _tokenIdCounter;
        if (currentSupply + recipients.length > MAX_SUPPLY) {
            revert AirdropExceedsMaxSupply();
        }
        for (uint256 i = 0; i < recipients.length; ++i) {
            uint256 tokenId = _tokenIdCounter;
            ++_tokenIdCounter;
            _safeMint(recipients[i], tokenId);
        }
    }
    /**
     * @notice Authorizes an upgrade to a new implementation contract.
     * @dev Required by the UUPS pattern. Restricted to the owner.
     * @param newImplementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        // solhint-disable-previous-line no-empty-blocks
    }
}
