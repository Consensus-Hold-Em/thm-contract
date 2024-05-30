/// This module contains a dummy store implementation where anyone can purchase
/// the same book for any amount of SUI greater than zero. The store owner can
/// collect the proceeds using the `StoreOwnerCap` capability.
///
/// In the tests section, we use the `test_scenario` module to simulate a few
/// transactions and test the store functionality. The test scenario is a very
/// powerful tool which can be used to simulate multiple transactions in a single
/// test.
///
/// The reference for this module is the "Black Books" TV series.
module consensus_holdem::black_books {
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};

    /// Trying to purchase the book for 0 SUI.
    const ECantBeZero: u64 = 0;

    /// A store owner capability. Allows the owner to collect proceeds.
    public struct StoreOwnerCap has key, store { id: UID }

    /// The "Black Books" store located in London.
    /// Only sells one book: "The Little Book of Calm".
    public struct BlackBooks has key {
        id: UID,
        balance: Balance<SUI>,
    }

    /// The only book sold by the Black Books store.
    public struct LittleBookOfCalm has key, store { id: UID }

    /// Share the store object and transfer the store owner capability to the sender.
    fun init(ctx: &mut TxContext) {
        transfer::transfer(StoreOwnerCap {
            id: object::new(ctx)
        }, ctx.sender());

        transfer::share_object(BlackBooks {
            id: object::new(ctx),
            balance: balance::zero()
        })
    }

    /// Purchase the "Little Book of Calm" for any amount of SUI greater than zero.
    public fun purchase(
        store: &mut BlackBooks, coin: Coin<SUI>, ctx: &mut TxContext
    ): LittleBookOfCalm {
        assert!(coin.value() > 0, ECantBeZero);
        store.balance.join(coin.into_balance());

        // create a new book
        LittleBookOfCalm { id: object::new(ctx) }
    }

    /// Collect the proceeds from the store and return them to the sender.
    public fun collect(
        store: &mut BlackBooks, _cap: &StoreOwnerCap, ctx: &mut TxContext
    ): Coin<SUI> {
        let amount = store.balance.value();
        store.balance.split(amount).into_coin(ctx)
    }

    // === Tests ===

    #[test_only]
    // The `init` is not run in tests, and normally a test_only function is
    // provided so that the module can be initialized in tests. Having it public
    // is important for tests located in other modules.
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // using a test-only attibute because this dependency can't be used in
    // production code and `sui move build` will complain about unused imports.
    //
    // the `sui::test_scenario` module is only available in tests.
    #[test_only] use sui::test_scenario;

    #[test]
    // This test uses `test_scenario` to emulate actions performed by 3 accounts.
    // A single scenario follows this structure:
    //
    // - `begin` - starts the first tx and creates the sceanario
    // - `next_tx` ... - starts the next tx and sets the sender
    // - `end` - wraps up the scenario
    //
    // It provides functions to start transactions, get the `TxContext, pull
    // objects from account inventory and shared pool, and check transaction
    // effects.
    //
    // In this test scenario:
    // 1. Bernard opens the store;
    // 2. Manny buys the book for 10 SUI and sends it to Fran;
    // 3. Fran sends the book back and buys it herself for 5 SUI;
    // 4. Bernard collects the proceeds and transfers the store to Fran;
    fun the_book_store_drama() {
        // it's a good idea to name addresses for readability
        // Bernard is the store owner, Manny is searching for the book,
        // and Fran is the next door store owner.
        let (bernard, manny, fran) = (@0x1, @0x2, @0x3);

        // create a test scenario with sender; initiates the first transaction
        let mut scenario = test_scenario::begin(bernard);

        // === First transaction ===

        // run the module initializer
        // we use curly braces to explicitly scope the transaction;
        {
            // `test_scenario::ctx` returns the `TxContext`
            init_for_testing(scenario.ctx());
        };

        // `next_tx` is used to initiate a new transaction in the scenario and
        // set the sender to the specified address. It returns `TransactionEffects`
        // which can be used to check object changes and events.
        let prev_effects = scenario.next_tx(manny);

        // make assertions on the effects of the first transaction
        let created_ids = prev_effects.created();
        let shared_ids = prev_effects.shared();
        let sent_ids = prev_effects.transferred_to_account();
        let events_num = prev_effects.num_user_events();

        assert!(created_ids.length() == 2, 0);
        assert!(shared_ids.length() == 1, 1);
        assert!(sent_ids.size() == 1, 2);
        assert!(events_num == 0, 3);

        // === Second transaction ===

        // we will store the `book_id` in a variable so we can use it later
        let book_id = {
            // test scenario can pull shared and sender-owned objects
            // here we pull the store from the pool
            let mut store = scenario.take_shared<BlackBooks>();
            let ctx = scenario.ctx();
            let coin = coin::mint_for_testing<SUI>(10_000_000_000, ctx);

            // call the purchase function
            let book = store.purchase(coin, ctx);
            let book_id = object::id(&book);

            // send the book to Fran
            transfer::transfer(book, fran);

            // now return the store to the pool
            test_scenario::return_shared(store);

            // return the book ID so we can use it across transactions
            book_id
        };

        // === Third transaction ===

        // next transaction - Fran looks in her inventory and finds the book
        // she decides to return it to Manny and buy another one herself
        scenario.next_tx(fran);
        {
            // objects can be taken from the sender by ID (if there's multiple)
            // or if there's only one object: `take_from_sender<T>(&scenario)`
            let book = scenario.take_from_sender_by_id<LittleBookOfCalm>(book_id);
            // send the book back to Manny
            transfer::transfer(book, manny);

            // now repeat the same steps as before
            let mut store = scenario.take_shared<BlackBooks>();
            let ctx = scenario.ctx();
            let coin = coin::mint_for_testing<SUI>(5_000_000_000, ctx);

            // same as before - purchase the book
            let book = store.purchase(coin, ctx);
            transfer::transfer(book, fran);

            // don't forget to return
            test_scenario::return_shared(store);
        };

        // === Fourth transaction ===

        // last transaction - Bernard collects the proceeds and transfers the store to Fran
        test_scenario::next_tx(&mut scenario, bernard);
        {
            let mut store = scenario.take_shared<BlackBooks>();
            let cap = scenario.take_from_sender<StoreOwnerCap>();
            let ctx = scenario.ctx();
            let coin = store.collect(&cap, ctx);

            transfer::public_transfer(coin, bernard);
            transfer::transfer(cap, fran);
            test_scenario::return_shared(store);
        };

        // finally, the test scenario needs to be finalized
        scenario.end();
    }
}
