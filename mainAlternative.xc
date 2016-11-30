// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 16                  //image height
#define  IMWD 16                  //image width
#define  WRKRS 9                 //number of worker threads, min: 2, max: 9

char infname[] = "test.pgm";     //put your input image path here
char outfname[] = "testout.pgm"; //put your output image path here

typedef unsigned char uchar;      //using uchar as shorthand for an unsigned character
//commented out as apparently this type is defined somewhere else
//typedef unsigned int uint;        //using uint as shorthand for an unsigned integer
typedef signed char byte;      //using byte as shorthand for a signed character

on tile[0]: port p_scl = XS1_PORT_1E;         //interface ports to orientation
on tile[0]: port p_sda = XS1_PORT_1F;

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

//total number of worker threads
const int NUMBER_OF_WORKERS = WRKRS;
//the height of the grid
const int GRID_HEIGHT = IMHT;
//width of the grid
const int GRID_WIDTH = IMWD;
//value of an alive cell
const byte ALIVE_CELL = 1;
//value of a dead cell
const byte DEAD_CELL = 0;

/*
 * interface for communication between workers
 */
interface WorkerWorker {
    /*
     * Returns 1 if the cell at the given column
     * in the top row is alive and 0 otherwise
     */
    byte getTopRowCell(int column);

    /*
     * Returns 1 if the cell at the given column
     * in the bottom row is alive and 0 otherwise
     */
    byte getBottomRowCell(int column);
};

/*
 * Interface for communication between a distributor and a worker
 */
interface DistributorWorker {
    /*
     * Initialises the subgrid of the worker by allocating
     * space able to hold data for rowCount*columnCount cells
     */
    void initialiseSubgrid(int rowCount, int columnCount);

    /*
     * Sets the initial value of cell at the given row and column
     * of the worker's subgrid to cellValue
     */
    void initialiseCell(byte cellValue, int row, int column);

    /*
     * Start computing next generation of cells of the game
     */
    void runEvolution(byte allowComputingBorderCells);

    /*
     * Return the value in the worker's subgrid
     * from the current generation at the given row and column
     */
    byte getCurrentGenerationCell(int row, int column);

    /*
     * Get the number of rows in the worker's subgrid
     */
    int getSubgridHeight();

    /*
     * Get the number of columns in the worker's subgrid
     */
     int getSubgridWidth();

     /*
      * Returns the number of live cells
      * in the current generation
      */
     int getNumberOfLiveCells();

     /*
      * Returns true if finished evolution, false otherwise
      */
     byte hasFinishedEvolution();

     /*
      * Pauses worker
      */
     void pause();

     /*
      * Resumes worker
      */
     void resume();

     /*
      * Gives permission to the worker
      * to compute cells that are on the border
      * with another worker. Part of the deadlock
      * prevention mechanism
      */
     void enableComputingBorderCells();

     /*
      * After all nodes have completed the evolution
      * call this on each one to make
      * the next generation subgrid the current generation
      */
     byte updateGenerationSubgrid();
};

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out)
{
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ ) {
      c_out <: line[ x ];
      printf( "-%4.1d ", line[ x ] ); //show image values
    }
    printf( "\n" );
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
//
/////////////////////////////////////////////////////////////////////////////////////////

/*
 * Returns the value of the cell in the next generation
 */
byte getCellNextGenerationValue(byte currentGenerationCellValue, byte liveNeighbouringCells) {
    byte nextGenerationCellValue = DEAD_CELL; //cause why not
    if(currentGenerationCellValue == ALIVE_CELL) {
        if(liveNeighbouringCells == 2 || liveNeighbouringCells == 3) {
        nextGenerationCellValue = currentGenerationCellValue; //it is unaffected
        }
    } else if(liveNeighbouringCells == 3){
        nextGenerationCellValue = ALIVE_CELL; //rising from the dead
    }
    return nextGenerationCellValue;
}

/*
 * Get the worker index working on the given row index number
 */
byte getWorkerForRow(int row) {
    //avoiding potential overflow and making the function more flexible
    row = row % GRID_HEIGHT;

    //all workers will get at least this number of rows to work with
    int baseNumberOfRowsPerWorker = GRID_HEIGHT / NUMBER_OF_WORKERS;

    //finding the remainder of rows. First extraRows number of workers will get one extra row to work with
    //in order to distribute the rows as evenly as possible
    int extraRows = GRID_HEIGHT % NUMBER_OF_WORKERS;

    //now the logic for computing which worker the current row belongs to:
    //find the last row for a woker working with an extra row
    int lastExtraRowIndex = extraRows * (baseNumberOfRowsPerWorker + 1) - 1; //-1 since it's 0-based
    byte workerIndex = 0;
    if(row <= lastExtraRowIndex) {
        //row belongs to one of the first workers with an extra row to work with
        workerIndex = row / (baseNumberOfRowsPerWorker + 1);
    } else {
        //row belongs to one of the rest of workers with base number of rows to work with
        workerIndex = (row - lastExtraRowIndex - 1) / baseNumberOfRowsPerWorker + extraRows;
    }
    return workerIndex;
}

/*
 * Returns the first index in the global grid
 * that the given worker is responsible for
 */
int getFirstRowIndexForWorker(byte workerIndex) {
    //all workers will get at least this number of rows to work with
    int baseNumberOfRowsPerWorker = GRID_HEIGHT / NUMBER_OF_WORKERS;

    //finding the remainder of rows. First extraRows number of workers will get one extra row to work with
    //in order to distribute the rows as evenly as possible
    int extraRows = GRID_HEIGHT % NUMBER_OF_WORKERS;

    int numberOfPreviousWorkersWithExtraRows = extraRows;
    if(workerIndex < extraRows) numberOfPreviousWorkersWithExtraRows = workerIndex;
    return workerIndex*baseNumberOfRowsPerWorker + numberOfPreviousWorkersWithExtraRows;
}

/*
 * definition of the worker thread. takes an interface for
 * communication with the distributor and four more interface
 * instances for bidirectional communication with the 2 adjacent workers
 */
void worker(server interface DistributorWorker distributorToWorker,
        server interface WorkerWorker upperWorkerClient,
        server interface WorkerWorker lowerWorkerClient,
        client interface WorkerWorker upperWorkerServer,
        client interface WorkerWorker lowerWorkerServer)
{
    /* we will dynamically allocate memory with calloc.
     * this would also mean it would be 0-filled on initialization
     */
    //pointer to memory for current generation
    byte *subgridCurrentGeneration;
    //pointer to memory for next generation
    byte *subgridNextGeneration;
    //the height and width of the 2 subgrids
    int rows, columns;
    byte workerPaused = true;
    byte finishedEvolution = true;
    //this value will be used for deadlock prevention
    byte allowedComputingBorderCells = false;
    //indicates if the worker has already computed
    //the next generations for the inner cells
    byte doneComputingInnerCells = false;
    //row of the cell currently being computed
    int currentRowComputing = 0;
    //column of the cell currently being computed
    int currentColumnComputing = 0;
    int numberOfEvolutions = 0;
    //the number of live cells in the current generation
    int numberOfLiveCellsInCurrentGeneration = 0;
    //the number of live cells in the next generation
    int numberOfLiveCellsInNextGeneration = 0;
    //offsets for neighbouring cells
    byte offsets[8][2] = {
            {-1, -1}, //upper-left corner
            {-1, 0},  //middle of upper row
            {-1, 1},  //upper-right corner
            {0, 1},   //on the right
            {0, -1},  //on the left
            {1, 1},   //lower-right corner
            {1, 0},   //middle of lower row
            {1, -1}   //lower-left corner
    };

    //printf("\nWorker: worker started!\n");
    while(true) {
        select {
            case distributorToWorker.initialiseSubgrid(int rowCount, int columnCount):
                    rows = rowCount;
                    columns = columnCount;
                    subgridCurrentGeneration  = (byte *) calloc(rows*columns, sizeof(byte));
                    subgridNextGeneration  = (byte *) calloc(rows*columns, sizeof(byte));
                    printf("Worker: thread configured\n");
                    break;
            case distributorToWorker.initialiseCell(byte cellValue, int row, int column):
                    //printf("Worker: initialise cell case entered\n");
                    subgridCurrentGeneration[columns*row + column] = cellValue;
                    if(cellValue == ALIVE_CELL) ++numberOfLiveCellsInCurrentGeneration;
                    break;
            case distributorToWorker.updateGenerationSubgrid() -> byte isUpdated:
                    //cleverly moving the memory of the next generation
                    //onto the one of the current generation
                    byte *temp = subgridCurrentGeneration;
                    subgridCurrentGeneration = subgridNextGeneration;
                    subgridNextGeneration = temp;
                    numberOfLiveCellsInCurrentGeneration = numberOfLiveCellsInNextGeneration;
                    numberOfLiveCellsInNextGeneration = 0;
                    isUpdated = true;
                    break;
            case distributorToWorker.runEvolution(byte allowComputingBorderValues):
                    //printf("\nWorker: run evolution case entered\n");
                    finishedEvolution = false;
                    workerPaused = false;
                    currentColumnComputing = 0;
                    //skip border row
                    currentRowComputing = 1;
                    allowedComputingBorderCells = allowComputingBorderValues;
                    doneComputingInnerCells = false;
                    break;
            case distributorToWorker.getCurrentGenerationCell(int row, int column) -> byte cellValue:
                    //printf("\nWorker: getCurrentGenerationCell case entered\n");
                    cellValue = subgridCurrentGeneration[columns*row + column];
                    break;
            case distributorToWorker.getSubgridHeight() -> int subgridHeight:
                    printf("\nWorker: getSubgridHeight case entered\n");
                    subgridHeight = rows;
                    break;
            case distributorToWorker.getSubgridWidth() -> int subgridWidth:
                    printf("\nWorker: getSubgridWidth case entered\n");
                    subgridWidth = columns;
                    break;
            case distributorToWorker.getNumberOfLiveCells() -> int numberOfLiveCells:
                    //printf("\nWorker: getNumberOfLiveCells case entered\n");
                    numberOfLiveCells = numberOfLiveCellsInCurrentGeneration;
                    break;
            case distributorToWorker.pause():
                    printf("\nWorker: pause case entered\n");
                    workerPaused = true;
                    break;
            case distributorToWorker.resume():
                    //printf("\nWorker: resume case entered\n");
                    workerPaused = false;
                    break;
            case distributorToWorker.hasFinishedEvolution() -> byte finishedEv:
                    //printf("\nWorker: hasFinishedEvolution case entered\n");
                    finishedEv = finishedEvolution;
                    break;
            case upperWorkerClient.getTopRowCell(int column) -> byte cellValue:
                    //printf("\nWorker: getTopRowCell case entered\n");
                    column = column % columns; //just in case of overflow
                    cellValue = subgridCurrentGeneration[column];
                    break;
            case lowerWorkerClient.getTopRowCell(int column) -> byte cellValue:
                    //printf("\nWorker: getTopRowCell case entered\n");
                    column = column % columns; //just in case of overflow
                    cellValue = subgridCurrentGeneration[column];
                    break;
            case upperWorkerClient.getBottomRowCell(int column) -> byte cellValue:
                    //printf("\nWorker: getBottomRowCell case entered\n");
                    column = column % columns; //just in case of overflow
                    cellValue = subgridCurrentGeneration[columns*(rows-1) + column];
                    break;
            case lowerWorkerClient.getBottomRowCell(int column) -> byte cellValue:
                    //printf("\nWorker: getBottomRowCell case entered\n");
                    column = column % columns; //just in case of overflow
                    cellValue = subgridCurrentGeneration[columns*(rows-1) + column];
                    break;
            case distributorToWorker.enableComputingBorderCells():
                    allowedComputingBorderCells = true;
                    break;
            default:
                /*
                 * When nobody demands stuff from the worker
                 * they could finally get back to work,
                 * i.e compute cells for the next generation
                 * if an evolution is currently being run
                 */
                //printf("\nWorker: default case entered\n");
                if(!workerPaused && !finishedEvolution) {
                    //compute cell in the current row and column
                    //printf("\nWorker: computing stuff\n");
                    if(doneComputingInnerCells && !allowedComputingBorderCells) {
                        //we still have work to do but are not allowed
                        //to work on border cells yet, so do nothing for now
                        //printf("\nWorker: waiting for permission to work on border\n");
                        break;
                    } else if(doneComputingInnerCells) {
                        //were done with the inner cells
                        //and we got permission to work on border
                        //printf("\nWorker: done computing inner cells and got permission for border\n");
                        int rowIndexes[2] = {0, rows-1};
                        for(int z = 0; z < 2; ++z) {
                            //avoiding an edge case where the number of rows for
                            //the worker ar just 1, so the first row would be
                            //processed twice
                            if(z == 1 && (rowIndexes[0] == rowIndexes[1])) break;
                            int currentRow = rowIndexes[z];
                            for(int currentColumn = 0; currentColumn < columns; ++currentColumn) {
                                //logic for computing current inner cell
                                byte liveNeighbouringCells = 0;
                                byte currentGenerationCellValue =
                                        subgridCurrentGeneration[columns*currentRow + currentColumn];
                                for(byte i = 0; i < 8; ++i) {
                                    int neighbourCellRow = currentRow + offsets[i][0];
                                    //avoiding under/overflows on the columns
                                    int neighbourCellColumn = (currentColumn + offsets[i][1] + columns) % columns;
                                    byte neighbourCellValue = DEAD_CELL; //assuming the worst :(

                                    //figuring out the value of the current neighbouring cell
                                    if(neighbourCellRow < 0) {
                                        //neighbour cell belongs to upper worker, request its value
                                        //printf("\nWorker: request cell from upper worker\n");
                                        neighbourCellValue = upperWorkerServer.getBottomRowCell(neighbourCellColumn);
                                    } else if(neighbourCellRow >= rows) {
                                        //neighbour cell belongs to lower worker, request its value
                                        //printf("\nWorker: request cell from lower worker\n");
                                        neighbourCellValue = lowerWorkerServer.getTopRowCell(neighbourCellColumn);
                                    } else {
                                        //cell belongs to current worker
                                        neighbourCellValue =
                                                subgridCurrentGeneration[neighbourCellRow*columns + neighbourCellColumn];
                                    }
                                    //if it hasn't kicked the bucket yet, increment the counter
                                    if(neighbourCellValue == ALIVE_CELL) ++liveNeighbouringCells;
                                 } //end of for loop

                                 //we got the number of alive neighbour cells
                                 //now we just have to compute the value of the
                                 //cell in the next generation
                                 byte nextGenerationCellValue =
                                         getCellNextGenerationValue(currentGenerationCellValue, liveNeighbouringCells);
                                 //putting its value in the next generation subgrid
                                 subgridNextGeneration[columns*currentRow + currentColumn] =
                                         nextGenerationCellValue;
                                 //increase the counter of live cells in next generation if applicable
                                 if(nextGenerationCellValue == ALIVE_CELL) ++numberOfLiveCellsInNextGeneration;
                            }
                        }

                        //were done with this generation, evolution complete
                        allowedComputingBorderCells = false;
                        finishedEvolution = true;
                        ++numberOfEvolutions;

                    } else {
                        //we need to work on inner cells first
                        if(currentRowComputing >= rows - 1 || (currentRowComputing == rows-2 && currentColumnComputing == columns-1)) {
                            //we are done with the inner cells
                            doneComputingInnerCells = true;
                            break;
                        }
                        byte liveNeighbouringCells = 0;
                        byte currentGenerationCellValue =
                                subgridCurrentGeneration[columns*currentRowComputing + currentColumnComputing];
                        for(byte i = 0; i < 8; ++i) {
                            int neighbourCellRow = currentRowComputing + offsets[i][0];
                            //avoiding under/overflows on the columns
                            int neighbourCellColumn = (currentColumnComputing + offsets[i][1] + columns) % columns;
                            //printf("\nWorker: currentRowComputing: %d, currentColumnComputing: %d, neighbourCellRow: %d, neighbourCellColumn: %d\n",
                                    //currentRowComputing, currentColumnComputing, neighbourCellRow, neighbourCellColumn);
                            byte neighbourCellValue = subgridCurrentGeneration[neighbourCellRow*columns + neighbourCellColumn];
                            //if it hasn't kicked the bucket yet, increment the counter
                            if(neighbourCellValue == ALIVE_CELL) ++liveNeighbouringCells;
                        }

                        //we got the number of alive neighbour cells
                        //now we just have to compute the value of the
                        //cell in the next generation
                        byte nextGenerationCellValue =
                                getCellNextGenerationValue(currentGenerationCellValue, liveNeighbouringCells);
                        //putting its value in the next generation subgrid
                        subgridNextGeneration[columns*currentRowComputing + currentColumnComputing] =
                                nextGenerationCellValue;
                        //increase the counter of live cells in next generation if applicable
                        if(nextGenerationCellValue == ALIVE_CELL) ++numberOfLiveCellsInNextGeneration;

                        //figure out which cell is next
                        if(currentRowComputing == rows-2 && currentColumnComputing == columns-1) {
                            //we are done with the inner cells
                            doneComputingInnerCells = true;
                        } else if(currentColumnComputing == columns-1){
                            ++currentRowComputing;
                            currentColumnComputing = 0;
                        } else {
                            ++currentColumnComputing;
                        }
                    }
                } else {
                    /*
                     * Either the worker is paused
                     * or they have finished computing
                     * the next generation.
                     * So the worker doesn't do anything
                     * until further instructions from
                     * the distributor
                     */
                    //printf("\nWorker: just chilling\n");
                }
                break;
        }
    }
}

void printCurrentGeneration(client interface DistributorWorker distributorToWorkerInterface[]) {
    printf("Distributor: current generation:\n");
    for(int row = 0; row < GRID_HEIGHT; ++row) {
        byte workerToSendCellTo = getWorkerForRow(row);
        int firstBelongingRowIndexOfWorker = getFirstRowIndexForWorker(workerToSendCellTo);
        int rowForWorkerSubgrid = row - firstBelongingRowIndexOfWorker;
        printf("worker: %d, ", workerToSendCellTo);
        for(int column = 0; column < GRID_WIDTH; ++column) {
            uchar currentCellValue =
                    distributorToWorkerInterface[workerToSendCellTo].getCurrentGenerationCell
                    (rowForWorkerSubgrid, column);
            printf("- %d -", currentCellValue);
        }
        printf("\n");
    }
}

/*
 * Completes a single evolution and returns
 * the time it taken to complete it
 */
uint32_t runAnotherEvolution(client interface DistributorWorker distributorToWorkerInterface[]) {
    uint32_t startTime, endTime;
    timer evolutionTimer;
    evolutionTimer :> startTime;
    //avoids deadlock by allowing only a single
    //worker to be computing border cells at any given time
    for(byte i = 0; i < NUMBER_OF_WORKERS; ++i) {
        distributorToWorkerInterface[i].runEvolution(false);
    }
    byte currentWorkerComputingBorders = 0;
    distributorToWorkerInterface[currentWorkerComputingBorders].enableComputingBorderCells();

    while(currentWorkerComputingBorders < NUMBER_OF_WORKERS) {
        while(!distributorToWorkerInterface[currentWorkerComputingBorders].hasFinishedEvolution()) {
            //just wait until it is done computing border cell values
        }
        //it is done, now give permission to next one
        ++currentWorkerComputingBorders;
        if(currentWorkerComputingBorders < NUMBER_OF_WORKERS) {
            //printf("\nDistributor: enabling worker: %d to work on border cells...\n", currentWorkerComputingBorders);
            distributorToWorkerInterface[currentWorkerComputingBorders].enableComputingBorderCells();
        }
    }
    //evolution complete
    //now tell them to update their current generation with the computed one
    for(byte i = 0; i < NUMBER_OF_WORKERS; ++i) {
        byte isUpated = distributorToWorkerInterface[i].updateGenerationSubgrid();
    }
    //now we are done with the whole evolution cycle :)
    evolutionTimer :> endTime;
    return endTime - startTime;
}

/*
 * Completes N evolutions and returns
 * the time taken to complete them
 */
uint32_t runEvolutions(int howManyTimes, client interface DistributorWorker distributorToWorkerInterface[]) {
    uint32_t totalTime = 0;
    for(int i = 0; i < howManyTimes; ++i) {
        totalTime += runAnotherEvolution(distributorToWorkerInterface);
    }
    return totalTime;
}

/*
 * Returns the number of live cells in the current generation
 */
int getNumberOfLiveCells(client interface DistributorWorker distributorToWorkerInterface[]) {
    int totalLiveCells = 0;
    for(int i = 0; i < NUMBER_OF_WORKERS; ++i) {
        int workerLiveCells = distributorToWorkerInterface[i].getNumberOfLiveCells();
        totalLiveCells += workerLiveCells;
        //printf("Distributor: Live cells in worker %d: %d\n", i, workerLiveCells);
    }
    return totalLiveCells;
}

//distributes the grid workload to the worker threads
void distributor(chanend gridInputChannel,
        chanend gridOutputChannel,
        chanend accelerometerInputChannel,
        client interface DistributorWorker distributorToWorkerInterface[])
{
    printf("Distributor: distributor started!\n");
    printf("Distributor: Now configuring workers...\n");
    for(byte i = 0; i < NUMBER_OF_WORKERS; ++i) {
        //all workers will get at least this number of rows to work with
        int baseNumberOfRowsPerWorker = GRID_HEIGHT / NUMBER_OF_WORKERS;
        //the first extraRows number of workers will have one extra row to work with
        int extraRows = GRID_HEIGHT % NUMBER_OF_WORKERS;
        int currentWorkerRows = baseNumberOfRowsPerWorker;
        if(i < extraRows) ++currentWorkerRows;
        distributorToWorkerInterface[i].initialiseSubgrid(currentWorkerRows, GRID_WIDTH);
    }
    printf("Distributor: workers configured\n");
    printf("Distributor: starting to read input image with height: %d and width: %d\n", GRID_HEIGHT, GRID_WIDTH);
    for(int row = 0; row < GRID_HEIGHT; ++row) {
        byte workerToSendCellTo = getWorkerForRow(row);
        int firstBelongingRowIndexOfWorker = getFirstRowIndexForWorker(workerToSendCellTo);
        int rowForWorkerSubgrid = row - firstBelongingRowIndexOfWorker;
        for(int column = 0; column < GRID_WIDTH; ++column) {
            uchar currentCellValue;
            gridInputChannel :> currentCellValue;  //read the current pixel value
            byte cellState = (currentCellValue == 255) ? ALIVE_CELL : DEAD_CELL;
            //since the initial memory allocation will fill memory with 0-s
            //we can skip cell values with 0-value state
            if(cellState == 0) continue;
            distributorToWorkerInterface[workerToSendCellTo].initialiseCell(cellState, rowForWorkerSubgrid, column);
        }
    }
    printf("\nDistributor: initial state distributed to workers!\n");

    for(int i = 1; i <= 100; ++i) {
        printf("Distributor: running %d evolution...\n", i);
        uint32_t timeTaken = runAnotherEvolution(distributorToWorkerInterface);
        int liveCells = getNumberOfLiveCells(distributorToWorkerInterface);
        printf("Distributor: time taken: %d, number of live cells in this generation: %d\n", timeTaken, liveCells);
        printCurrentGeneration(distributorToWorkerInterface);
    }

}
/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in)
{
  int res;
  uchar line[ IMWD ];

  //Open PGM file
  printf( "DataOutStream: Start...\n" );
  res = _openoutpgm( outfname, IMWD, IMHT );
  if( res ) {
    printf( "DataOutStream: Error opening %s\n.", outfname );
    return;
  }

  //Compile each line of the image and write the image line-by-line
  for( int y = 0; y < IMHT; y++ ) {
    for( int x = 0; x < IMWD; x++ ) {
      c_in :> line[ x ];
    }
    _writeoutline( line, IMWD );
    printf( "DataOutStream: Line written...\n" );
  }

  //Close the PGM image
  _closeoutpgm();
  printf( "DataOutStream: Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;
  int tilted = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }
  
  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the orientation x-axis forever
  while (1) {

    //check until new orientation data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt
    if (!tilted) {
      if (x>30) {
        tilted = 1 - tilted;
        toDist <: 1;
      }
    }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {
    /* two interface instances for every adjacent pair of workers
    * as they'll need to both read and write from each other
    * explanation for why using the WRKRS macro instead of the constant:
    * https://www.xcore.com/forum/viewtopic.php?f=47&t=4776&view=next
    */
    interface WorkerWorker workerToWorkerInterface[WRKRS][2];

    /* an interface for communication between
    * the distributor and every worker thread
    */
    interface DistributorWorker distributorToWorkerInterface[WRKRS];

    i2c_master_if i2c[1];               //interface to orientation

    chan c_inIO, c_outIO, c_control;    //extend your channel definitions here

    par {
        on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
        on tile[0]: orientation(i2c[0],c_control);        //client thread reading orientation data
        on tile[1]: DataInStream(infname, c_inIO);          //thread to read in a PGM image
        on tile[1]: DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
        on tile[1]: distributor(c_inIO, c_outIO, c_control, distributorToWorkerInterface);//thread to coordinate work
        par(byte i = 0; i < WRKRS; ++i)
            //byte upperWorker = (i == 0) ? NUMBER_OF_WORKERS-1 : i-1;
            //byte lowerWorker = (i == NUMBER_OF_WORKERS-1) ? 0 : i+1;
            //distribute workers on both tiles to utilize memory better
            on tile[(i < WRKRS/2) ? 0 : 1]: worker(distributorToWorkerInterface[i],
                workerToWorkerInterface[i][0],
                workerToWorkerInterface[i][1],
                workerToWorkerInterface[(i == 0) ? WRKRS-1 : i-1][1],
                workerToWorkerInterface[(i == WRKRS-1) ? 0 : i+1][0]);
      }

    return 0;
}
