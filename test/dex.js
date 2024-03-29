const { expectRevert } = require('@openzeppelin/test-helpers');
const Dai = artifacts.require('mocks/Dai.sol');
const Bat = artifacts.require('mocks/Bat.sol');
const Rep = artifacts.require('mocks/Rep.sol');
const Zrx = artifacts.require('mocks/Zrx.sol');
const Dex = artifacts.require('mocks/Dex.sol');

const SIDE = {
  BUY: 0,
  SELL: 1
};


contract('Dex', (accounts) => {
  let dai, bat, rep, zrx, dex;

  const[trader1, trader2] = [accounts[1], accounts[2]];
  const [DAI, BAT, REP, ZRX] = ['DAI', 'BAT', 'REP', 'ZRX']
    .map(ticker => web3.utils.fromAscii(ticker));
  beforeEach(async() => {
    ([dai, bat, rep, zrx] = await Promise.all([
      Dai.new(),
      Bat.new(),
      Rep.new(),
      Zrx.new()
    ]));
    dex = await Dex.new();

    await Promise.all([
      dex.addToken(DAI, dai.address),
      dex.addToken(BAT, bat.address),
      dex.addToken(REP, rep.address),
      dex.addToken(ZRX, zrx.address)
    ]);

    const amount = web3.utils.toWei('1000');
    const seedTokenBalance = async (token, trader) => {
      await token.faucet(trader, amount);
      await token.approve(
        dex.address,
        amount,
        {from: trader}
      );
    };

    await Promise.all(
      [dai, bat, rep, zrx].map(
        token => seedTokenBalance(token, trader1)
      )
    );
    await Promise.all(
        [dai, bat, rep, zrx].map(
          token => seedTokenBalance(token, trader2)
        )
      );
  });

it('should deposit tokens', async () => {
  const amount = web3.utils.toWei('100');

  await dex.deposit(
    amount,
    DAI,
    {from: trader1}
  );

  const balance = await dex.traderBalances(trader1, DAI);
  assert(balance.toString() === amount);
});

it('should not deposit token if token doesnt exist', async () =>{
  await expectRevert(
    dex.deposit(
      web3.utils.toWei("100"),
      web3.utils.fromAscii('RANDOM-TOKEN'),
      {from: trader1}
    ),
    'token does not exist'
  );
});

it('should be able to withdraw', async () =>{
  const amount = web3.utils.toWei('100');

  await dex.deposit(
    amount,
    DAI,
    {from: trader1}
  );

  let balance = await dex.traderBalances(trader1, DAI);
  assert(balance.toString() === amount)

  await dex.withdraw(
    amount,
    DAI,
    {from: trader1}
  );

  balance = await dex.traderBalances(trader1, DAI);
  assert(balance.toString() === "0")
});

it('is able to create a limit order', async () => {

  await dex.deposit(
    web3.utils.toWei('100'),
    DAI,
    {from: trader1}
  );


  await dex.createLimitOrder(
    REP,
    web3.utils.toWei('10'),
    10,
    SIDE.BUY,
    {from: trader1}
  );

  let buyOrders = await dex.getOrders(REP, SIDE.BUY);
  let sellOrders = await dex.getOrders(REP, SIDE.SELL);

  assert(buyOrders.length === 1);
  assert(buyOrders[0].trader === trader1);
  assert(buyOrders[0].ticker === web3.utils.padRight(REP, 64));
  assert(buyOrders[0].price === '10');
  assert(buyOrders[0].amount === web3.utils.toWei('10'));
  assert(sellOrders.length === 0);


  await dex.deposit(
    web3.utils.toWei('200'),
    DAI,
    {from: trader2}
  );


  await dex.createLimitOrder(
    REP,
    web3.utils.toWei('10'),
    11,
    SIDE.BUY,
    {from: trader2}
  );

   buyOrders = await dex.getOrders(REP, SIDE.BUY);
   sellOrders = await dex.getOrders(REP, SIDE.SELL);


    assert(buyOrders.length === 2);
    assert(buyOrders[0].trader === trader2);
    assert(buyOrders[1].trader === trader1);
    assert(sellOrders.length === 0);

    await dex.createLimitOrder(
      REP,
      web3.utils.toWei('10'),
      9,
      SIDE.BUY,
      {from: trader2}
    );

    buyOrders = await dex.getOrders(REP, SIDE.BUY);
    sellOrders = await dex.getOrders(REP, SIDE.SELL);

    assert(buyOrders.length === 3);
    assert(buyOrders[0].trader === trader2);
    assert(buyOrders[1].trader === trader1);
    assert(buyOrders[2].trader === trader2);
    assert(buyOrders[2].price === '9');
    assert(sellOrders.length === 0);
});

});
