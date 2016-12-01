// define it before any functions, so basically on top of all actual functions
// like global variables
on tile[0] : in port buttons = XS1_PORT_4E; //port to access xCore-200 buttons
on tile[0] : out port leds = XS1_PORT_4F;   //port to access xCore-200 LEDs

// global variables
// try different colors
const int OFF = 0;
const int GREENSMALL = 1;
const int BLUE = 2;
const int GREEN = 4;
const int RED = 8;



// put it in main() par function
// you can change the tile number, but you have to change the one on the top too
        on tile[0]: LEDs(leds, toLEDs);
        on tile[0]: buttonfunction(buttons, toDis);

// this is the function for LED
// to make it work, you need to put "toLEDs <: somevariable" in other function
// which "somevariable" needs to be the corresponding colors shown above
void LEDs(out port Port, chanend toLEDs){
    int light;
    while(1){
        toLEDs :> light;
        Port <: light;      //Output whatever received
    }
}


// button function

void buttonfunction (in port Port, chanend toDis){
    int r;
    while(1){
        Port when pinsneq(15) :> r;
        // you can assign numbers 13 and 14 to variables
        // they are basically 2 buttons on the xmos board
        if ((r == 13) || (r == 14)){
           toDis <: r;
        }
        Port when pinseq(15) :> r;
        break;
    }
}

// in order to stop the evolution during a loop, you need to make a if statement in that function
// which verify which button is pressed (13 || 14), and then do the stop condiction
// for example
/*    for(int i = 1; i <= 100; ++i) {
        int button = 0;
        toDis :> button;
        if(button == 13){
            stop the for loop
        }
        printf("Distributor: running %d evolution...\n", i);
        uint32_t timeTaken = runAnotherEvolution(distributorToWorkerInterface);
        int liveCells = getNumberOfLiveCells(distributorToWorkerInterface);
        printf("Distributor: time taken: %d, number of live cells in this generation: %d\n", timeTaken, liveCells);
        printCurrentGeneration(distributorToWorkerInterface);
    }
*/
