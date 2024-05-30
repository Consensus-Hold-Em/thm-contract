/// Module: consensus_holdem
module consensus_holdem::consensus_holdem {

    use sui::table::{Table};
    use sui::balance::{Balance};
    use sui::coin::{Self,Coin};
    use sui::sui::SUI;
    use sui::event::{Self};

    // rounds
    const DECK_SETUP: u8 = 0;
    const PREFLOP_ROUND: u8 = 1;
    const FLOP_ROUND: u8 = 2;
    const TURN_ROUND: u8 = 3;
    const RIVER_ROUND: u8 = 4;
    const GAME_FINISHED: u8 = 5;
    const GAME_NOT_STARTED: u8 = 6;

    const PLAYER_LIMIT: u64 = 6;

    public struct CardTable has key, store {
        id: UID,
        buy_in: u64,
        small_blind: u64,
        big_blind: u64,
        
        players: vector<address>,
        chips: Table<address, Balance<SUI>>, // buy-in
        
        current_pot: Balance<SUI>,
        round: u8, // tracks the betting round
        turn: u64, // tracks the player index who's turn it is
        deck: vector<EncryptedCard>
    }

    public struct EncryptedCard has copy, drop, store {
        in: vector<u8>,
        c1: vector<u8>,
        c2: vector<u8>,
    }

    public struct StartingHandState has copy, drop {
        player_cards: vector<EncryptedCard>,
        flop: vector<EncryptedCard>,
        river: vector<EncryptedCard>,
        turn: vector<EncryptedCard>
    }

    public struct StartHandEvent has copy, drop {
        table_id: ID,
        player_id: u64,
        public_key: vector<u8>,
        hand_state: StartingHandState,
        commitment: vector<u8>
    }

    public struct ShuffleAndDecryptEvent has copy, drop {
        table_id: ID,
        player_id: u64,
        deck: vector<EncryptedCard>
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

    public struct StartBettingEvent has copy, drop {
        table_id: ID,
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
    public entry fun create_table(coin: Coin<SUI>, buy_in: u64, small_blind: u64, big_blind: u64, ctx: &mut TxContext)  {
        let mut v = vector::empty<address>();
        v.push_back(ctx.sender());
        let chips = sui::table::new<address, Balance<SUI>>(ctx);

        let mut card_table = CardTable {
            id: object::new(ctx),
            buy_in: buy_in,
            small_blind: small_blind,
            big_blind: big_blind,
            players: v,
            chips: chips,
            current_pot: sui::coin::zero(ctx).into_balance(),
            round: GAME_NOT_STARTED,
            turn: 0,
            deck: vector::empty<EncryptedCard>()
        };

        buy_in(&mut card_table, coin, ctx);

        event::emit(CreateTableEvent {
            table_id: object::id(&card_table),
            player: ctx.sender(),
        });

        transfer::share_object(card_table);
    }

    // someone can join an existing table
    public entry fun join_table(card_table: &mut CardTable, coin: Coin<SUI>, ctx: &mut TxContext) {
        // TODO PLAYER_LIMIT
        assert!(card_table.players.length() >= PLAYER_LIMIT, 0);
        card_table.buy_in(coin, ctx);
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
        if (card_table.chips.contains(ctx.sender()) == true) {
            let current_amount = card_table.chips.borrow_mut(ctx.sender());
            current_amount.join(coin.into_balance());
        } else {
            card_table.chips.add(ctx.sender(), coin.into_balance());
        }
    }

    // start_hand sets up the initial values for the hand for each players encrypted
    // card locations. This is called by every player in order from small blind to the 
    // last player hand 
    public fun start_hand(card_table: &mut CardTable, player_id: u64, public_key: vector<u8>,
        commitment: vector<u8>, hand_state: StartingHandState, ctx: &mut TxContext) {
        assert!(card_table.round >= GAME_FINISHED, 0);

        // TODO: assert player_id submitted matches current turn order, which we are not tracking now.
        
        let addr = ctx.sender();

        // small blind
        if (player_id == 0) {
            //let chips = card_table.chips.borrow_mut(addr);
            // Assert that the balance for this player is > small_blind, if not reject
            // NOTE: we do not update the balance until we start.
        };

        // big blind, same as the small
        if (player_id == 1) {
            // Assert that the balance for this player is > big_blind, if not reject
            // NOTE: we do not update the balance until we start.
        };

        event::emit(StartHandEvent {
            table_id: object::id(card_table),
            player_id: player_id,
            public_key: public_key,
            hand_state: hand_state,
            commitment: commitment
        });

        if (player_id == card_table.players.length()-1) {
            // Subtract the balance for the small_blind and big_blind

            card_table.round = DECK_SETUP;
            
            event::emit(StartGameEvent {
                table_id: object::id(card_table),
                players: card_table.players
            });
        }
    }

    public fun ShuffleAndDecrypt(card_table: &mut CardTable, player_id: u64, shuffled: vector<EncryptedCard>, ctx: &mut TxContext) {
        event::emit(ShuffleAndDecryptEvent {
            table_id: object::id(card_table),
            player_id: player_id,
            deck: shuffled
        });

        if (player_id == card_table.players.length() - 1) {
            card_table.round = PREFLOP_ROUND; 

            event::emit(StartBettingEvent {
                table_id: object::id(card_table)
            });
        }
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

        card_table.current_pot.join(coin.into_balance());
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
            pot_size: card_table.current_pot.value(),
            round: round
        })
    }

    public entry fun withdraw(card_table: &mut CardTable, ctx: &mut TxContext) {
        // TODO some kind of assert?
        let total_balance = card_table.current_pot.value();
        let coin = coin::take(&mut card_table.current_pot, total_balance, ctx);
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
        create_table(coin, 100, 0, 1, &mut ctx);
    }

    #[test_only] use sui::test_scenario;

    #[test]
    fun test_join_table() {
        let (p1, p2, p3) = (@0x1, @0x2, @0x3);

        let mut scenario = test_scenario::begin(p1);
        let ctx = scenario.ctx();
        let coin = coin::mint_for_testing<SUI>(10_000, ctx);
        create_table(coin, 100, 0, 1, ctx);

        let prev_effects = scenario.next_tx(p2);

        {
            let mut card_table = scenario.take_shared<CardTable>();
            let ctx = scenario.ctx();
            let coin = coin::mint_for_testing<SUI>(7_000, ctx);
            join_table(&mut card_table, coin, ctx);
            // number of players at the table is correct
            assert!(card_table.players.length() == 2, 0);
            test_scenario::return_shared(card_table);
        };

        let prev_effects2 = scenario.next_tx(p3);

        {
            let mut card_table = scenario.take_shared<CardTable>();
            let ctx = scenario.ctx();
            let coin = coin::mint_for_testing<SUI>(2_000, ctx);
            join_table(&mut card_table, coin, ctx);
            assert!(card_table.players.length() == 3, 0);
            test_scenario::return_shared(card_table);
        };

        scenario.end();
    }

    #[test]
    fun test_start_game() {
        let (p1, p2, p3) = (@0x1, @0x2, @0x3);
        // let mut scenario = test_scenario::begin(p1);

    }
}

