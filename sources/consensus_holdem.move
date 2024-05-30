/// Module: consensus_holdem
module consensus_holdem::consensus_holdem {

    // use sui::table::{Table};
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

    public struct CardTable has key, store {
        id: UID,
        players: vector<address>,
        player_limit: u8, // not used so far but could be implemented in join_table()
        pot_size: Balance<SUI>, // ? maybe this is Coin since this would be actual sui tokens being sent
        round: u8, // tracks the betting round
        turn: u64 // tracks the player index who's turn it is
    }

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
    public entry fun create_table(coin: Coin<SUI>, ctx: &mut TxContext):  {
        let mut v = vector::empty<address>();
        v.push_back(ctx.sender());

        let card_table = CardTable {
            id: object::new(ctx),
            players: v,
            player_limit: 6,
            pot_size: coin.into_balance(),
            round: GAME_NOT_STARTED,
            turn: 0,
        };

        event::emit(CreateTableEvent {
            table_id: object::id(&card_table),
            player: ctx.sender(),
        });

        transfer::share_object(card_table);
    }

    // someone can join an existing table
    public entry fun join_table(card_table: &mut CardTable, ctx: &mut TxContext) {
        card_table.players.push_back(ctx.sender());

        event::emit(JoinTableEvent {
            table_id: object::id(card_table),
            player: ctx.sender(),
        })
    }

    public entry fun small_blind(card_table: &mut CardTable) {
        card_table.players.borrow(0);
    }

    // set the initial values for the card table and game
    public entry fun start_game(card_table: &mut CardTable, ctx: &mut TxContext) {
        assert!(card_table.round >= GAME_FINISHED, 1);

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
        assert!(p == ctx.sender(), 1);

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

        // test_scenario::next_tx(&mut scenario, p2);

        let mut card_table = scenario.take_shared<CardTable>();

        // join_table(&mut scenario, ctx);
        // let _ = {
        //     let mut card_table = scenario.take_shared<CardTable>();
        //     card_table.join_table(ctx);
        //     1
        // }

        scenario.end();
    }
}

