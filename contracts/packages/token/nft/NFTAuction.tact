/*
    This file provides traits for the NFT Auction contract, allowing users to bid on NFTs. 
    When the auction ends, the NFT goes to the highest bidder and the seller receives the bid amount. 

    Reference:
    [Official Implementation](https://github.com/ton-blockchain/token-contract/blob/991bdb4925653c51b0b53ab212c53143f71f5476/nft/nft-marketplace.fc)
    [Official Implementation](https://github.com/ton-blockchain/token-contract/blob/991bdb4925653c51b0b53ab212c53143f71f5476/nft/nft-sale.fc)
    [NFT Auction Template](https://github.com/avolabs-io/nft-auction)
*/

trait NFTAuctionStandard {
    virtual const minTonsForStorage: Int = ton("0.03");
    virtual const gasConsumption: Int = ton("0.03");

    owner: Address;
    nftAddress: Address;
    auctionInfo: AuctionInfo;
    auctionEnd: Int;
    isInitialized: Int;

    //********************************************//
    //                  Messages                  //
    //********************************************//

    // @dev Default receive function to receive funds
    receive() {}

    // @dev Initializes the auction when called by the owner
    receive("BuildNftAuction") {
        let cxt: Context = context();
        if(cxt.sender != self.owner) {
            throw(1001); // Only owner can build nft auction contract
        }
        if(self.isInitialized != 0) {
            throw(1004); // Contract is already initialized
        }
        self.isInitialized = 1;
        self.auctionEnd = 0;
    }

    // @dev Accepts bids for the NFT as long as the auction is active
    receive("Bid") {
        // Check if auction is still active.
        if(now() > self.auctionEnd && self.auctionEnd != 0 && self.isInitialized == 0) {
            throw(1005); // Auction ended.
        }

        let cxt: Context = context();
        let buyer: Address = cxt.sender;
        if(buyer == self.auctionInfo.nftSeller) {
            throw(1006); //NFT Seller cannot bid.
        }
        let bidValue: Int = cxt.value;
        let buyNowPrice: Int = self.auctionInfo.buyNowPrice;
        if(bidValue >= buyNowPrice) {
            self.auctionInfo.nftHighestBid = bidValue;
            // Pay winning bid amount to seller.
            self._send_winning_bid_amount();
            // Transfer NFT to buyer
            self._transfer_nft(buyer);
            self.isInitialized = 0;
            return;
        }

        let bidIncreaseAmount: Int = (self.auctionInfo.nftHighestBid * (10000 + self.auctionInfo.bidIncreasePercentage)) / 10000;
        if(bidValue <= bidIncreaseAmount) {
            throw(1007); // Bid doesn't meet the minimum increase requirement.
        }
        // Send back previous highest bid to previous highest bidder.
        let prevNftHighestBidder: Address = self.auctionInfo.nftHighestBidder;
        let prevNftHighestBid: Int = self.auctionInfo.nftHighestBid;
        let paybackTon: Int = max(prevNftHighestBid - self.minTonsForStorage - self.gasConsumption,0);
        send(SendParameters{
            to: prevNftHighestBidder,
            value: paybackTon, 
            mode: SendPayGasSeparately, 
            bounce: true,
            body: "Pay bid money back to the prevNftHighestBidder".asComment()
        });
        // Update highest bid and Transfer ton back to previous highest bidder.
        self.auctionInfo.nftHighestBidder = cxt.sender;
        self.auctionInfo.nftHighestBid = bidValue;
        // If bid value is greater than reserve price, then the auction is being started.
        if (bidValue > self.auctionInfo.reservePrice) {
            self._update_auction_end();
        }
    }

    // @dev Settles the auction, transferring the NFT to the highest bidder and the funds to the seller
    receive("settleAuction") {
        if(now() < self.auctionEnd) {
            throw(1000); // Auction not yet ended.
        }
        // Pay winning bid amount to seller.
        self._send_winning_bid_amount();

        // Transfer NFT to buyer
        let buyer: Address = self.auctionInfo.nftHighestBidder;
        self._transfer_nft(buyer);
        self.isInitialized = 0;
    }

    //********************************************//
    //             Internal functions             //
    //********************************************//

    // @dev Updates the auction end time based on the latest bid and the defined auction bid period
    virtual inline fun _update_auction_end() {
        self.auctionEnd = now() + self.auctionInfo.auctionPeriod;
    }

    // @dev Transfer the NFT to the highest bidder
    // @note If you want change msg value, you should make sure that is enough for NFT Auction market contract to transfer NFT.
    virtual inline fun _transfer_nft(buyer: Address) {
        send(SendParameters{
            to: self.owner, 
            value: ton("0.06"), 
            bounce: false,
            mode: SendPayGasSeparately,
            body: TransferNFT {
                nftAddress: self.nftAddress,
                seller: self.auctionInfo.nftSeller,
                query_id: 0,
                new_owner: buyer,
                response_destination: buyer,
                custom_payload: emptyCell(),
                forward_amount: 0,
                forward_payload: emptyCell()
            }.toCell()
        });
    }

    // @dev Transfers the highest bid amount to the seller
    virtual inline fun _send_winning_bid_amount() {
        let seller: Address = self.auctionInfo.nftSeller;
        let winningBidAmount: Int = self.auctionInfo.nftHighestBid;
        send(SendParameters{
            to: seller,
            value: winningBidAmount, 
            mode: SendPayGasSeparately, 
            bounce: true,
            body: "Pay winning bid amount".asComment()
        });
    }

    // @dev Initializes the auction end time to 0, allowing the seller to auction the NFT again in the future
    virtual inline fun _init_auction_end() {
        let cxt: Context = context();
        if(cxt.sender != self.owner) {
            throw(1001); // Only owner can init auction end time.
        }
        self.auctionEnd = 0;
    }

    //*********************************//
    //             Getters             //
    //*********************************//

    // @dev Returns the current auction information
    get fun get_auctin_info(): AuctionInfo {
        return self.auctionInfo;
    }

    // @dev Checks if the auction is initialized and returns the state (1 for initialized, 0 otherwise)
    get fun get_is__initialized(): Int {
        return self.isInitialized;
    }

    // @dev Returns the end time of the auction
    get fun get_auction_end(): Int {
        return self.auctionEnd;
    }
}