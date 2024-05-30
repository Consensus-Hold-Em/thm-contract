/// Module: consensus_holdem
module consensus_holdem::consensus_holdem {

    use sui::table::{Table};
    use sui::balance::{Balance};
    use sui::coin::{Self,Coin};
    use sui::sui::SUI;
    use sui::event::{Self};

    // rounds
    const PREFLOP_ROUND: u8 = 0;
    const FLOP_ROUND: u8 = 1;
    const TURN_ROUND: u8 = 2;
    const RIVER_ROUND: u8 = 3;
    const GAME_FINISHED: u8 = 4;
    const GAME_NOT_STARTED: u8 = 5;

    const PLAYER_LIMIT: u8 = 6;

    public struct CardTable has key, store {
        id: UID,
        buy_in: u64,
        
        players: vector<address>,
        chips: Table<address, Balance<SUI>>, // buy-in
        
        current_pot: Balance<SUI>,
        round: u8, // tracks the betting round
        turn: u64, // tracks the player index who's turn it is
    }

    // TODO Create player objects that can be attached ?
    // for example can track player stats on chain

    // Events
    public struct CreateTableEvent has copy, drop {
        table_id: ID,
        player: address,
    }

    public struct JoinTableEvent has copy, drop {
        table_id: ID,
        player: address,
    }

    public struct StartGameEvent has copy, drop {
        table_id: ID,
        players: vector<address>,
    }

    public struct PlayerTurnEvent has copy, drop {
        table_id: ID,
        player: address,
        // turn: u8,
        // next_player: address,
        bet_size: u64,
        pot_size: u64,
        round: u8
    }

    public struct GameRoundEndEvent has copy, drop {
        table_id: ID,
        round: u8
    }

    public struct WithdrawEvent has copy, drop {
        table_id: ID,
        player: address,
    }

    // fun init(ctx: &mut TxContext) {}

    // someone creates the table
    // TODO add buy-in
    public entry fun create_table(coin: Coin<SUI>, buy_in: u64, ctx: &mut TxContext)  {
        let mut v = vector::empty<address>();
        v.push_back(ctx.sender());
        let chips = sui::table::new<address, Coin<SUI>>(ctx);

        let card_table = CardTable {
            id: object::new(ctx),
            players: v,
            chips: chips,
            buy_in: buy_in,
            current_pot: coin.into_balance(), // TODO
            round: GAME_NOT_STARTED,
            turn: 0,
        };

        card_table.buy_in(coin, ctx);

        event::emit(CreateTableEvent {
            table_id: object::id(&card_table),
            player: ctx.sender(),
        });

        transfer::share_object(card_table);
    }

    // someone can join an existing table
    public entry fun join_table(card_table: &mut CardTable, ctx: &mut TxContext) {
        // TODO PLAYER_LIMIT
        assert!()
        card_table.players.push_back(ctx.sender());

        event::emit(JoinTableEvent {
            table_id: object::id(card_table),
            player: ctx.sender(),
        })
    }

    // handles the buy in
    public fun buy_in(card_table: &mut CardTable, coin: Coin<SUI>, ctx: &mut TxContext) {
        let coin_amount = coin.value();
        assert!(coin_amount >= card_table.buy_in, 0);

    }

    public entry fun small_blind(card_table: &mut CardTable) {
        card_table.players.borrow(0);
    }

    // set the initial values for the card table and game
    public entry fun start_game(card_table: &mut CardTable, ctx: &mut TxContext) {
        assert!(card_table.round >= GAME_FINISHED, 0);

        // set small blind which is just the first player in the array
        let p = card_table.players.pop_back();
        card_table.players.insert(p, 0);
        card_table.turn = 0;
        card_table.round = PREFLOP_ROUND;

        event::emit(StartGameEvent {
            table_id: object::id(card_table),
            players: card_table.players
        })
    }

    // 1) check valid player address ?? , 
    // 2) add their bet to the pot size
    // 3) handle round & turn
    public entry fun bet(card_table: &mut CardTable, coin: Coin<SUI>, ctx: &mut TxContext) {
        let p = card_table.players.borrow(card_table.turn);
        // check if the caller matches whose turn it is
        assert!(p == ctx.sender(), 0);

        // for the event
        let amount = coin.value();
        let round = card_table.round;

        card_table.pot_size.join(coin.into_balance());
        // check if it is the last player's turn
        if (card_table.turn == card_table.players.length() - 1) {
            card_table.turn = 0;
            card_table.round = card_table.round + 1;

            event::emit(GameRoundEndEvent {
                table_id: object::id(card_table),
                round: round
            })
        } else {
            card_table.turn = card_table.turn + 1;
        };

        event::emit(PlayerTurnEvent {
            table_id: object::id(card_table),
            player: ctx.sender(),
            bet_size: amount,
            pot_size: card_table.pot_size.value(),
            round: round
        })
    }

    public entry fun withdraw(card_table: &mut CardTable, ctx: &mut TxContext) {
        // TODO some kind of assert?
        let total_balance = card_table.pot_size.value();
        let coin = coin::take(&mut card_table.pot_size, total_balance, ctx);
        transfer::public_transfer(coin, ctx.sender());
        event::emit(WithdrawEvent {
            table_id: object::id(card_table),
            player: ctx.sender()
        })
    }

    // TODO handle winner
    #[test]
    fun test_create_table() {
        let mut ctx = tx_context::dummy();
        let coin = coin::mint_for_testing<SUI>(0, &mut ctx);
        create_table(coin , &mut ctx);
    }

    #[test_only] use sui::test_scenario;

    #[test]
    fun test_join_table() {
        let (p1, p2, p3) = (@0x1, @0x2, @0x3);

        let mut scenario = test_scenario::begin(p1);
        let ctx = scenario.ctx();
        let coin = coin::mint_for_testing<SUI>(0, ctx);
        create_table(coin , ctx);

        let prev_effects = scenario.next_tx(p2);

        {
            let mut card_table = scenario.take_shared<CardTable>();
            let ctx = scenario.ctx();
            join_table(&mut card_table, ctx);
            // number of players at the table is correct
            assert!(card_table.players.length() == 2, 0);
            test_scenario::return_shared(card_table);
        };

        let prev_effects2 = scenario.next_tx(p3);

        {
            let mut card_table = scenario.take_shared<CardTable>();
            let ctx = scenario.ctx();
            join_table(&mut card_table, ctx);
            assert!(card_table.players.length() == 3, 0);
            test_scenario::return_shared(card_table);
        };

        scenario.end();
    }

    #[test]
    fun test_start_game() {
        let (p1, p2, p3) = (@0x1, @0x2, @0x3);
        let mut scenario = test_scenario::begin(p1);


    }
}

