pragma solidity 0.6.3;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';

contract Dex{

    using SafeMath for uint;


    struct Token{
        bytes32 ticker;
        address tokenAddress;
    }

    enum Side {
        BUY,
        SELL
    }

    struct Order {
        uint id;
        address trader;
        Side side;
        bytes32 ticker;
        uint amount;
        uint filled;
        uint price;
        uint date;
    }

    mapping(bytes32 => Token) public tokens;

    bytes32[] public tokenList;

    mapping(address => mapping(bytes32 => uint)) public traderBalances;
    mapping(bytes32 => mapping(uint => Order[])) public orderBook;
    address public admin;
    uint public nextOrderId;
    uint public nextTradeId;
    bytes32 constant DAI = bytes32('DAI');

    event NewTrade(uint tradeId, uint orderId, bytes32 indexed ticker, address indexed trader1, address indexed trader2, uint amount, uint price);

    constructor() public {
        admin = msg.sender;
    }

    function getOrders(bytes32 ticker, Side side) external view returns(Order[] memory) {
      return orderBook[ticker][uint(side)];
  }

  function getTokens() external view returns(Token[] memory) {
      Token[] memory _tokens = new Token[](tokenList.length);
      for (uint i = 0; i < tokenList.length; i++) {
        _tokens[i] = Token(
          tokens[tokenList[i]].ticker,
          tokens[tokenList[i]].tokenAddress
        );
      }
      return _tokens;
    }

    function addToken(bytes32 ticker, address tokenAddress) onlyAdmin() external{
        tokens[ticker] = Token(ticker, tokenAddress);
        tokenList.push(ticker);
    }

    function deposit(uint amount, bytes32 ticker) tokenExists(ticker) external{
        IERC20(tokens[ticker].tokenAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker].add(amount);
    }

    function withdraw(uint amount, bytes32 ticker) tokenExists(ticker) external {
        require(traderBalances[msg.sender][ticker] >= amount, 'balance to low');
        traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker].sub(amount);
        IERC20(tokens[ticker].tokenAddress).transfer(msg.sender, amount);
    }

    function createLimitOrder(bytes32 ticker, uint amount, uint price, Side side) tokenIsntDai(ticker) tokenExists(ticker) external {

        if(side == Side.SELL) {
            require(traderBalances[msg.sender][ticker] >= amount, 'token balance too low');
        } else {
            require(traderBalances[msg.sender][DAI] >= amount.mul(price), 'not enough DAI');
        }

        Order[] storage orders = orderBook[ticker][uint(side)];
        orders.push(Order(
            nextOrderId,
            msg.sender,
            side,
            ticker,
            amount,
            0,
            price,
            now
        ));

        uint i = orders.length > 0 ? orders.length -1 : 0;
        while (i>0){
            if (side == Side.BUY && orders[i-1].price > orders[i].price) {
                break;
            }
            if (side == Side.SELL && orders[i-1].price < orders[i].price){
                break;
            }
            Order memory order = orders[i - 1];
            orders[i-1] = orders[i];
            orders[i] = order;
            i= i.sub(1);
        }
        nextOrderId = nextOrderId.add(1);
    }


    function createMarketOrder(bytes32 ticker, uint amount, Side side) tokenIsntDai(ticker) tokenExists(ticker) external{

        if (side == Side.BUY) {
              require(traderBalances[msg.sender][ticker] >= amount, 'token balance too low');
        }

        Order[] storage orders = orderBook[ticker][uint (side == Side.BUY ? Side.SELL : Side.BUY)];
        uint i=0;
        uint remaining = amount;

        while(i< orders.length && remaining > 0){
            uint available = orders[i].amount.sub(orders[i].filled);
            uint matched = (remaining > available) ? available : remaining;
            remaining = remaining.sub(matched);
            orders[i].filled = orders[i].filled.add(matched);
            emit NewTrade(
                nextTradeId,
                orders[i].id,
                ticker,
                orders[i].trader,
                msg.sender,
                matched,
                orders[i].price
            );

            if(side == Side.SELL){

                traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker].sub(matched);
                traderBalances[msg.sender][DAI] =  traderBalances[msg.sender][DAI].add(matched.mul(orders[i].price));

                traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker].add(matched);
                traderBalances[msg.sender][DAI] =  traderBalances[msg.sender][DAI].sub(matched.mul(orders[i].price));
            }

            if (side == Side.BUY){
                require(traderBalances[msg.sender][DAI] >= matched * orders[i].price, 'not enough DAI');

                traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker].add(matched);
                traderBalances[msg.sender][DAI] =  traderBalances[msg.sender][DAI].sub(matched.mul(orders[i].price));

                traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker].sub(matched);
                traderBalances[msg.sender][DAI] =  traderBalances[msg.sender][DAI].add(matched.mul(orders[i].price));
            }
            nextTradeId = nextTradeId.add(1);
            i = i.add(1);
        }

        i = 0;
        while(i < orders.length && orders[i].filled == orders[i].amount){
            for(uint j = i; j < orders.length - 1; j++){
                orders[j] = orders[j+1];
            }
            orders.pop();
            i = i.add(1);
        }
    }



    modifier tokenIsntDai(bytes32 ticker){
        require(ticker != DAI, 'cannot trade DAI');
        _;
    }

    modifier tokenExists(bytes32 ticker){
        require (
            tokens[ticker].tokenAddress != address(0),
            'token does not exist'
            );
            _;
    }

    modifier onlyAdmin(){
        require(msg.sender == admin, 'only admin');
        _;
    }
}
