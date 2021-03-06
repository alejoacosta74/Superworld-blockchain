//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.0;   

// 0x0A7a9dd62Af0638DE94903235682d1630DF09Cf3 use for ropsten coin
// rinkeby 0x22E94603d5143db30b41653A0b96EEF1eAAaf051
// 10 percentage cut
// 1000000000000000 baseprice (test 0.001 ETH)
// 100000000000000000 baseprice (production 0.1 ETH)
// http://geo.superworldapp.com/api/json/metadata/get/ metaUrl

import "https://github.com/kole-swapnil/openzepkole/token/ERC721/ERC721.sol";
import "https://github.com/kole-swapnil/openzepkole/access/Ownable.sol";
import "https://github.com/kole-swapnil/Superworld-blockchain/String.sol";
import "https://github.com/kole-swapnil/Superworld-blockchain/Token.sol";
import "https://github.com/kole-swapnil/Superworld-blockchain/SuperWorldEvent.sol";

abstract contract ERC20Interface {
    // @dev checks whether the transaction between the two addresses of the token went through
    // @param takes in two addresses, and a single uint as a token number
    // @return returns a boolean, true is successful and false if not
    function transferFrom(
        address from,
        address to,
        uint256 tokens
    ) public virtual returns (bool success);

    // @dev checks the balance of the inputted address
    // @param the address you are checking the balance of
    // @return returns the balance as a uint
    function balanceOf(address tokenOwner)
        public
        virtual
        view
        returns (uint256 balance); //"constant" deprecated at 0.5.0
}

// SuperWorldToken contract inherits ERC721 and ownable contracts
contract SuperWorldToken is ERC721, Ownable {
    // address public owner;
    address public coinAddress;
    ERC20Interface public superWorldCoin;

    uint256 public percentageCut;
    uint256 public basePrice;
    uint256 public buyId = 0;
    uint256 public listId = 0;
    string public metaUrl;

    // tokenId => bought price in wei
    mapping(uint256 => uint256) public boughtPrices;

    // tokenId => sell price in wei
    mapping(uint256 => uint256) public sellPrices;

    // tokenId => is selling
    mapping(uint256 => bool) public isSellings;
    // tokenId => buyId
    mapping(uint256 => uint256) public buyIds;
    
    // events
    // TODO: add timestamp (block or UTC)

    constructor(
        address _coinAddress,
        uint256 _percentageCut,
        uint256 _basePrice,
        string memory _metaUrl
    ) public ERC721("SuperWorld", "SUPERWORLD") {
        coinAddress = _coinAddress;
        superWorldCoin = ERC20Interface(coinAddress);
        percentageCut = _percentageCut;
        basePrice = _basePrice;
        metaUrl = _metaUrl;
        buyId = 0;
        listId = 0;
        _setBaseURI(metaUrl);
    }
    
    // @dev creates a base price that has to be greater than zero for the token
    // @param takes in a uint that represents the baseprice you want.
    // @return no return, mutator
    function setBasePrice(uint256 _basePrice) public onlyOwner() {
        require(_basePrice > 0);
        basePrice = _basePrice;
    }

    // @dev sets the percentage cut of the token for the contract variable
    // @param takes in a uint representing the percentageCut
    // @return no return, mutator
    function setPercentageCut(uint256 _percentageCut) public onlyOwner() {
        require(_percentageCut > 0);
        percentageCut = _percentageCut;
    }

    // @dev generates a new token, using recordTransactions directly below, private method
    // @param takes in a buyer address, the id of the token, and the price of the token
    // @return returns nothing, creates a token 
    function createToken(
        address buyer,
        uint256 tokenId,
        uint256 price
    ) private {
        _mint(buyer, tokenId);
        recordTransaction(tokenId, price);
    }

    // @dev used by createToken, adds to the array at the token id spot, the price of the token based on its id
    // @param takes the token's id and the price of the tokenId
    // @return returns nothing
    function recordTransaction(uint256 tokenId, uint256 price) private {
        boughtPrices[tokenId] = price;
    }

    // @dev returns all info on the token using lat and lon
    // @param takes in two strings, latitude and longitude.
    // @return the token id, the address of the token owner, if it is owned, if it is up for sale, and the price it is
    //         going for in ether
    function getInfo(string memory lat, string memory lon)
        public
        view
        returns (
            bytes32 tokenId,
            address tokenOwner,
            bool isOwned,
            bool isSelling,
            uint256 price
        )
    {
        tokenId = Token.getTokenId(lat, lon);
        uint256 intTokenId = uint256(tokenId);
        if (_tokenOwners.contains(intTokenId)) {
            tokenOwner = _tokenOwners.get(intTokenId);
            isOwned = true;
        } else {
            tokenOwner = address(0);
            isOwned = false;
        }
        isSelling = isSellings[intTokenId];
        price = getPrice(intTokenId);
    }
    
    // Bulk transfer
    // @dev gives tokens to users at no cost
    // @param string of latitudes and longitudes, formatted "lat1,lon1;lat2,lon2;...;latn,lonn",
    //        array [address1, address2, ..., addressn], array [buyPrice1, ..., buyPricen]
    // @return none
    function giftTokens(
        string memory geoIds,
        address[] memory buyers,
        uint256[] memory buyPrices
    ) public onlyOwner() {
        require(bytes(geoIds).length != 0);
        uint256 n = 1;
        for (uint256 pos = String.indexOfChar(geoIds, byte(";"), 0); pos != 0; pos = String.indexOfChar(geoIds, byte(";"), pos + 1)) {
            n++;
        }
        require(n == buyers.length);
        require(n == buyPrices.length);
        
        _giftTokens(geoIds, buyers, buyPrices, n);
    }
    
    // @dev private helper function for giftTokens
    // @param string of latitudes and longitudes, formatted "lat1,lon1;lat2,lon2;...;latn,lonn",
    //        array [address1, address2, ..., addressn], array [buyPrice1, ..., buyPricen],
    //        number of tokens in the above lists
    // @return none
    function _giftTokens(
        string memory geoIds,
        address[] memory buyers,
        uint256[] memory buyPrices,
        uint256 numTokens
    ) private {
        string[] memory lat = new string[](numTokens);
        string[] memory lon = new string[](numTokens);

        uint256 pos = 0;
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 delim = String.indexOfChar(geoIds, byte(";"), pos);
            string memory geoId = String.substring(geoIds, pos, delim);
            lat[i] = Token.getLat(geoId);
            lon[i] = Token.getLon(geoId);
            pos = delim + 1;
        }

        for (uint256 i = 0; i < numTokens; i++) {
            _giftToken(lat[i], lon[i], buyers[i], buyPrices[i]);
        }
    }
    
    // @dev private function using lat and lon to transfer a user
    // @param takes in a geo location(lat and lon), as well as a user's address price they bought at (in old contract)
    // @return returns nothing, but logs to the transaction logs of the even Buy Token
    function _giftToken(
        string memory lat,
        string memory lon,
        address buyer,
        uint256 buyPrice
    ) private {
        uint256 tokenId = uint256(Token.getTokenId(lat, lon));
        createToken(buyer, tokenId, buyPrice);
        emitBuyTokenEvents(
            tokenId,
            lon,
            lat,
            buyer,
            address(0),
            buyPrice,
            now
        );
    }
    
    // Bulk listing
    // @dev list tokens gifted through giftTokens
    // @param string of latitudes and longitudes, formatted "lat1,lon1;lat2,lon2;...;latn,lonn",
    //        array [sellingPrice1, ..., sellingPricen]
    // @return none
    function relistTokens(
        string memory geoIds,
        uint256[] memory sellingPrices
    ) public onlyOwner() {
        require(bytes(geoIds).length != 0);
        uint256 n = 1;
        for (uint256 pos = String.indexOfChar(geoIds, byte(";"), 0); pos != 0; pos = String.indexOfChar(geoIds, byte(";"), pos + 1)) {
            n++;
        }
        require(n == sellingPrices.length);
        
        _relistTokens(geoIds, sellingPrices, n);
    }
    
    // @dev helper function for relistTokens
    // @param string of latitudes and longitudes, formatted "lat1,lon1;lat2,lon2;...;latn,lonn",
    //        array [sellingPrice1, ..., sellingPricen], number of items in above arrays
    // @return none
    function _relistTokens(
        string memory geoIds,
        uint256[] memory sellingPrices,
        uint256 numTokens
    ) private {
        string[] memory lat = new string[](numTokens);
        string[] memory lon = new string[](numTokens);

        uint256 pos = 0;
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 delim = String.indexOfChar(geoIds, byte(";"), pos);
            string memory geoId = String.substring(geoIds, pos, delim);
            lat[i] = Token.getLat(geoId);
            lon[i] = Token.getLon(geoId);
            pos = delim + 1;
        }

        for (uint256 i = 0; i < numTokens; i++) {
            _relistToken(lat[i], lon[i], sellingPrices[i]);
        }
    }
    
    // @dev takes in the geolocation to relist the token on the market, and lists the property for sale
    // @param takes in a geolocation and the price sold at
    // @return returns nothing, but logs to transactions using ListTokens event
    function _relistToken(
        string memory lat,
        string memory lon,
        uint256 sellingPrice
    ) private {
        uint256 tokenId = uint256(Token.getTokenId(lat, lon));
        require(_tokenOwners.contains(tokenId));
        
        isSellings[tokenId] = true;
        sellPrices[tokenId] = sellingPrice;
        emitListTokenEvents(
            buyIds[tokenId],
            lon,
            lat,
            _tokenOwners.get(tokenId),
            sellingPrice,
            true,
            now
        );
    }
    
    // @dev get approval for the transaction to go through
    // @param takes in a buyer address, a seller address, and the coins spending, as well as the data with the transaction?
    // @return returns nothing, emits a event receive approval obj, and logs it to transactions
    function receiveApproval(
        address buyer,
        uint256 coins,
        address _coinAddress,
        bytes32 _data
    ) public {
        emit SuperWorldEvent.EventReceiveApproval(buyer, coins, _coinAddress, _data);
        require(_coinAddress == coinAddress);
        string memory dataString = String.bytes32ToString(_data);
        buyTokenWithCoins(buyer, coins, Token.getLat(dataString), Token.getLon(dataString));
    }

    // @dev Indicates the status of transfer (false if it didnt go through)
    // @param takes in the buyer address, the coins spent,and the geolocation of the token
    // @return returns the status of the transfer of coins for the token
    function buyTokenWithCoins(
        address buyer,
        uint256 coins,
        string memory lat,
        string memory lon
    ) public returns (bool) {
        uint256 tokenId = uint256(Token.getTokenId(lat, lon));
        // address seller = _tokenOwners.get(tokenId);

        if (!_tokenOwners.contains(tokenId)) {
            // not owned
            require(coins >= basePrice);
            require(superWorldCoin.balanceOf(buyer) >= basePrice);
            if (!superWorldCoin.transferFrom(buyer, address(this), basePrice)) {
                return false;
            }
            createToken(buyer, tokenId, basePrice);
            _tokenOwners.set(tokenId, buyer);
            emitBuyTokenEvents(
                tokenId,
                lon,
                lat,
                buyer,
                address(0),
                basePrice,
                now
            );
            return true;
        }
        return false;
    }
    
    // @dev Buy multiple tokens at once. Note that if the request is invalid or not enough ether is paid,
    //      no tokens will be bought
    // @param string of latitudes and longitudes, formatted "lat1,lon1;lat2,lon2;...;latn,lonn"
    // @return whether buying was successful
    function buyTokens(string memory geoIds) public payable returns (bool) {
        require(bytes(geoIds).length != 0);
        uint256 n = 1;
        for (uint256 pos = String.indexOfChar(geoIds, byte(";"), 0); pos != 0; pos = String.indexOfChar(geoIds, byte(";"), pos + 1)) {
            n++;
        }
        
        return _buyTokens(geoIds, msg.value, n);
    }
    
    // @dev private helper function for bulkBuy
    // @param string "lat1,lon1;lat2,lon2;...;latn,lonn", number of tokens to buy, amount paid (in wei)
    //        when calling bulkBuy
    // @return whether buying was successful
    function _buyTokens(
        string memory geoIds,
        uint256 offerPrice,
        uint256 numTokens
    ) private returns (bool) {
        string[] memory lat = new string[](numTokens);
        string[] memory lon = new string[](numTokens);
        uint256[] memory prices = new uint256[](numTokens);
        
        uint256 totalPrice = 0;
        uint256 pos = 0;
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 delim = String.indexOfChar(geoIds, byte(";"), pos);
            string memory geoId = String.substring(geoIds, pos, delim);
            lat[i] = Token.getLat(geoId);
            lon[i] = Token.getLon(geoId);
            pos = delim + 1;
            
            uint256 tokenId = uint256(Token.getTokenId(lat[i], lon[i]));
            prices[i] = getPrice(tokenId);
            totalPrice = SafeMath.add(totalPrice, prices[i]);
        }
        require(offerPrice >= totalPrice);
        
        for (uint256 i = 0; i < numTokens; i++) {
            if (!_buyToken(lat[i], lon[i], prices[i])) return false;
        }
        return true;
    }

    // @dev private helper function for buyToken
    // @param geoId, amount paid (in wei) when calling buyToken
    // @return whether buying was successful
    function _buyToken(string memory lat, string memory lon, uint256 offerPrice)
        private
        returns (bool)
    {
        uint256 tokenId = uint256(Token.getTokenId(lat, lon));
        
        // unique token not bought yet
        if (!EnumerableMap.contains(_tokenOwners, tokenId)) {
            require(offerPrice >= basePrice);
            createToken(msg.sender, tokenId, offerPrice);
            EnumerableMap.set(_tokenOwners, tokenId, msg.sender);
            emitBuyTokenEvents(
                tokenId,
                lon,
                lat,
                msg.sender,
                address(0),
                offerPrice,
                now
            );
            return true;
        }

        address seller = _tokenOwners.get(tokenId);
        // check selling
        require(isSellings[tokenId] == true);
        // check sell price > 0
        require(sellPrices[tokenId] > 0);
        // check offer price >= sell price
        require(offerPrice >= sellPrices[tokenId]);
        // check seller != buyer
        require(msg.sender != seller);

        // send percentage of cut to contract owner
        uint256 fee = SafeMath.div(
            SafeMath.mul(offerPrice, percentageCut),
            100
        );
        uint256 priceAfterFee = SafeMath.sub(offerPrice, fee);

        // mark not selling
        isSellings[tokenId] = false;

        // send payment
        address payable _seller = payable(seller);
        if (!_seller.send(priceAfterFee)) {
            // if failed to send, mark selling
            isSellings[tokenId] = true;
            return false;
        }

        // transfer token
        //removeTokenFrom(seller, tokenId);
        //addTokenTo(msg.sender, tokenId);
        //safeTransferFrom(seller, msg.sender, tokenId);
        
        _holderTokens[seller].remove(tokenId);
        _holderTokens[msg.sender].add(tokenId);
        recordTransaction(tokenId, offerPrice);
        sellPrices[tokenId] = offerPrice;
        _tokenOwners.set(tokenId, msg.sender);
        emitBuyTokenEvents(
            tokenId,
            lon,
            lat,
            msg.sender,
            seller,
            offerPrice,
            now
        );
        return true;
    }
    
    // @dev Updates contract state before transferring a token.
    // @param addresses of transfer, tokenId of token to be transferred
    // @return none
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);
        (string memory lat, string memory lon) = Token.getGeoFromTokenId(bytes32(tokenId));
        
        // For now, basePrice is a placeholder for the selling price of the token until we can find a way to
        // actually access the price. In particular, we need a way to set sellPrices[tokenId] when listing on OpenSea.
        isSellings[tokenId] = false;
        recordTransaction(tokenId, basePrice);
        emitBuyTokenEvents(
            tokenId,
            lon,
            lat,
            to,
            from,
            basePrice,
            now
        );
        sellPrices[tokenId] = basePrice;
    }

    // @dev allows the processing of buying a token using event emitting
    // @param takes in the token id, the geolocation, the address of the buyer and seller, the price of the offer and when it was bought.
    // @return returns nothing, but creates an event emitter that logs the buying of
    function emitBuyTokenEvents(
        uint256 tokenId,
        string memory lon,
        string memory lat,
        address buyer,
        address seller,
        uint256 offerPrice,
        uint256 timestamp
    ) private {
        buyId++;
        buyIds[tokenId] = buyId;
        emit SuperWorldEvent.EventBuyToken(
            buyId,
            lon,
            lat,
            buyer,
            seller,
            offerPrice,
            timestamp,
            bytes32(tokenId)
        );
        emit SuperWorldEvent.EventBuyTokenNearby(
            buyId,
            Token.getTokenId(String.truncateDecimals(lat, 1), String.truncateDecimals(lon, 1)),
            lon,
            lat,
            buyer,
            seller,
            offerPrice,
            timestamp
        );
    }

    // list / delist
    // @dev list the token on the superworld market, for a certain price user wants to sell at
    // @param takes in the geolocation of the token, and the price it is selling at
    // @return returns nothing, emits a ListToken event logging it to transactions.
    function listToken(
        string memory lat,
        string memory lon,
        uint256 sellPrice
    ) public {
        uint256 tokenId = uint256(Token.getTokenId(lat, lon));
        require(_tokenOwners.contains(tokenId));
        require(msg.sender == _tokenOwners.get(tokenId));
        isSellings[tokenId] = true;
        sellPrices[tokenId] = sellPrice;
        emitListTokenEvents(
            buyIds[tokenId],
            lon,
            lat,
            msg.sender,
            sellPrice,
            true,
            now
        );
    }

    // @dev take the token off the market
    // @param requests the geolocation of the token
    // @return returns nothing, emits a List Token even
    function delistToken(string memory lat, string memory lon) public {
        uint256 tokenId = uint256(Token.getTokenId(lat, lon));
        require(_tokenOwners.contains(tokenId));
        require(msg.sender == _tokenOwners.get(tokenId));
        isSellings[tokenId] = false;
        emitListTokenEvents(
            buyIds[tokenId],
            lon,
            lat,
            msg.sender,
            sellPrices[tokenId],
            false,
            now
        );
        sellPrices[tokenId] = 0;
    }

    // @dev does the list token event, used by many previous functions
    // @param takes in the buyerid, the geolocation, the seller address and price selling at, as well as whether it is listed or not, and when it sold
    // @return returns nothing, but emits the event List token to log to the transactions on the blockchain
    function emitListTokenEvents(
        uint256 _buyId,
        string memory lon,
        string memory lat,
        address seller,
        uint256 sellPrice,
        bool isListed,
        uint256 timestamp
    ) private {
        listId++;
        bytes32 tokenId = Token.getTokenId(lat, lon);
        emit SuperWorldEvent.EventListToken(
            listId,
            _buyId,
            lon,
            lat,
            seller,
            sellPrice,
            isListed,
            timestamp,
            tokenId
        );
        emit SuperWorldEvent.EventListTokenNearby(
            listId,
            _buyId,
            Token.getTokenId(String.truncateDecimals(lat, 1), String.truncateDecimals(lon, 1)),
            lon,
            lat,
            seller,
            sellPrice,
            isListed,
            timestamp
        );
    }
     
    // @dev provides the price for the tokenId
    // @param takes in the tokenId as a uint parameter
    // @return a uint of the price returned
    function getPrice(uint256 tokenId) public view returns (uint256) {
        if (!_tokenOwners.contains(tokenId)) {
            // not owned
            return basePrice;
        } else {
            // owned
            return isSellings[tokenId] ? sellPrices[tokenId] : boughtPrices[tokenId];
        }
    }

    // @devs: withdraws a certain amount from the owner
    // @param no params taken in
    // @return doesn't return anything, but transfers the balance from the message sender to the address intended.
    function withdrawBalance() public payable onlyOwner() {
        uint256 balance = address(this).balance;
        (msg.sender).transfer(balance);
    }
    
    // @devs: gets the metadata URL for a token.
    // @param tokenId
    // @return string containing the URL where the token's metadata is stored
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        string memory x = string(abi.encodePacked(metaUrl, '0x', String.toHexString(tokenId)));
        return x;
    }
}
