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
#define  WRKRS 8                  //number of worker threads, min: 2, max: 8

char infname[] = "test.pgm";     //put your input image path here
char outfname[] = "testout.pgm"; //put your output image path here

typedef unsigned char uchar;      //using uchar as shorthand for an unsigned character
//commented out as apparently this type is defined somewhere else
//typedef unsigned int uint;        //using unint as shorthand for an unsigned integer
typedef unsigned char ubyte;      //using ubyte as shorthand for an unsigned character
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
const uint NUMBER_OF_WORKERS = WRKRS;
//the height of the grid
const uint GRID_HEIGHT = IMHT;
//width of the grid
const uint GRID_WIDTH = IMWD;
//value of an alive cell
const ubyte ALIVE_CELL = 1;
//value of a dead cell
const ubyte DEAD_CELL = 0;

/*
 * interface for communication between workers
 */
interface WorkerWorker {
    /*
     * Returns 1 if the cell at the given column
     * in the top row is alive and 0 otherwise
     */
    ubyte getTopRowCell(uint column);

    /*
     * Returns 1 if the cell at the given column
     * in the bottom row is alive and 0 otherwise
     */
    ubyte getBottomRowCell(uint column);
};

/*
 * Interface for communication between a distributor and a worker
 */
interface DistributorWorker {
    /*
     * Initialises the subgrid of the worker by allocating
     * space able to hold data for rowCount*columnCount cells
     */
    void initialiseSubgrid(uint rowCount, uint columnCount);

    /*
     * Sets the initial value of cell at the given row and column
     * of the worker's subgrid to cellValue
     */
    void initialiseCell(ubyte cellValue, uint row, uint column);

    /*
     * Start computing next generation of cells of the game
     */
    void runEvolution();

    /*
     * Return the value in the worker's subgrid
     * from the current generation at the given row and column
     */
    ubyte getCurrentGenerationCell(uint row, uint column);

    /*
     * Get the number of rows in the worker's subgrid
     */
    uint getSubgridHeight();

    /*
     * Get the number of columns in the worker's subgrid
     */
     uint getSubgridWidth();

     /*
      * Returns the number of live cells
      * in the current generation
      */
     uint getNumberOfLiveCells();

     /*
      * Returns true if finished evolution, false otherwise
      */
     ubyte hasFinishedEvolution();

     /*
      * Pauses worker
      */
     void pause();

     /*
      * Resumes worker
      */
     void resume();
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
ubyte getCellNextGenerationValue(ubyte currentGenerationCellValue, ubyte liveNeighbouringCells) {
    ubyte nextGenerationCellValue = DEAD_CELL; //cause why not
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
ubyte getWorkerForRow(uint row) {
    //avoiding potential overflow and making the function more flexible
    row = row % GRID_HEIGHT;

    //all workers will get at least this number of rows to work with
    uint baseNumberOfRowsPerWorker = GRID_HEIGHT / NUMBER_OF_WORKERS;

    //finding the remainder of rows. First extraRows number of workers will get one extra row to work with
    //in order to distribute the rows as evenly as possible
    uint extraRows = GRID_HEIGHT % NUMBER_OF_WORKERS;

    //now the logic for computing which worker the current row belongs to:
    //find the last row for a woker working with an extra row
    uint lastExtraRowIndex = extraRows * (baseNumberOfRowsPerWorker + 1) - 1; //-1 since it's 0-based

    ubyte workerIndex = 0;
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
    ubyte *subgridCurrentGeneration;
    //pointer to memory for next generation
    ubyte *subgridNextGeneration;
    //the height and width of the 2 subgrids
    uint rows, columns;
    ubyte workerPaused = true;
    ubyte finishedEvolution = true;
    //row of the cell currently being computed
    uint currentRowComputing = 0;
    //column of the cell currently being computed
    uint currentColumnComputing = 0;
    uint numberOfEvolutions = 0;
    //the number of live cells in the current generation
    uint numberOfLiveCellsInCurrentGeneration = 0;
    //the number of live cells in the next generation
    uint numberOfLiveCellsInNextGeneration = 0;
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

    printf("Worker: worker started!\n");
    while(true) {
        select {
            case distributorToWorker.initialiseSubgrid(uint rowCount, uint columnCount):
                    rows = rowCount;
                    columns = columnCount;
                    subgridCurrentGeneration  = (ubyte *) calloc(rows*columns, sizeof(ubyte));
                    subgridNextGeneration  = (ubyte *) calloc(rows*columns, sizeof(ubyte));
                    printf("Worker: thread configured\n");
                    break;
            case distributorToWorker.initialiseCell(ubyte cellValue, uint row, uint column):
                    printf("Worker: initialise cell case entered\n");
                    *(subgridCurrentGeneration + row*rows + column) = cellValue;
                    if(cellValue == ALIVE_CELL) ++numberOfLiveCellsInCurrentGeneration;
                    break;
            case distributorToWorker.runEvolution():
                    printf("Worker: run evolution case entered\n");
                    finishedEvolution = false;
                    currentColumnComputing = 0;
                    currentRowComputing = 0;
                    break;
            case distributorToWorker.getCurrentGenerationCell(uint row, uint column) -> ubyte cellValue:
                    printf("Worker: getCurrentGenerationCell case entered\n");
                    cellValue = *(subgridCurrentGeneration + rows*row + column);
                    break;
            case distributorToWorker.getSubgridHeight() -> uint subgridHeight:
                    printf("Worker: getSubgridHeight case entered\n");
                    subgridHeight = rows;
                    break;
            case distributorToWorker.getSubgridWidth() -> uint subgridWidth:
                    printf("Worker: getSubgridWidth case entered\n");
                    subgridWidth = columns;
                    break;
            case distributorToWorker.getNumberOfLiveCells() -> uint numberOfLiveCells:
                    printf("Worker: getNumberOfLiveCells case entered\n");
                    numberOfLiveCells = numberOfLiveCellsInCurrentGeneration;
                    break;
            case distributorToWorker.pause():
                    printf("Worker: pause case entered\n");
                    workerPaused = true;
                    break;
            case distributorToWorker.resume():
                    printf("Worker: resume case entered\n");
                    workerPaused = false;
                    break;
            case distributorToWorker.hasFinishedEvolution() -> ubyte finishedEv:
                    printf("Worker: hasFinishedEvolution case entered\n");
                    finishedEv = finishedEvolution;
                    break;
            case upperWorkerClient.getTopRowCell(uint column) -> ubyte cellValue:
                    printf("Worker: getTopRowCell case entered\n");
                    column = column % columns; //just in case of overflow
                    cellValue = *(subgridCurrentGeneration + column);
                    break;
            case lowerWorkerClient.getTopRowCell(uint column) -> ubyte cellValue:
                    printf("Worker: getTopRowCell case entered\n");
                    column = column % columns; //just in case of overflow
                    cellValue = *(subgridCurrentGeneration + column);
                    break;
            case upperWorkerClient.getBottomRowCell(uint column) -> ubyte cellValue:
                    printf("Worker: getBottomRowCell case entered\n");
                    column = column % columns; //just in case of overflow
                    cellValue = *(subgridCurrentGeneration + rows*(rows-1) + column);
                    break;
            case lowerWorkerClient.getBottomRowCell(uint column) -> ubyte cellValue:
                    printf("Worker: getBottomRowCell case entered\n");
                    column = column % columns; //just in case of overflow
                    cellValue = *(subgridCurrentGeneration + rows*(rows-1) + column);
                    break;

            default:
                /*
                 * When nobody demands stuff from the worker
                 * they could finally get back to work,
                 * i.e compute cells for the next generation
                 * if an evolution is currently being run
                 */
                printf("Worker: default case entered\n");
                if(!workerPaused && !finishedEvolution) {
                    //compute cell in the current row and column
                    // vars currentRowComputing & currentColumnComputing
                    printf("Worker: computing stuff\n");
                    ubyte liveNeighbouringCells = 0;
                    ubyte currentGenerationCellValue =
                            *(subgridCurrentGeneration + rows*currentRowComputing + currentColumnComputing);
                    for(ubyte i = 0; i < 8; ++i) {
                        int neighbourCellRow = i + offsets[i][0];
                        //avoiding under/overflows on the columns
                        int neighbourCellColumn = (i + offsets[i][1] + columns) % columns;
                        ubyte neighbourCellValue = DEAD_CELL; //assuming the worst :(

                        //figuring out the value of the current neighbouring cell
                        if(neighbourCellRow < 0) {
                            //neighbour cell belongs to upper worker, request its value
                            neighbourCellValue = upperWorkerServer.getBottomRowCell(neighbourCellColumn);
                        } else if(neighbourCellRow >= rows) {
                            //neighbour cell belongs to lower worker, request its value
                            neighbourCellValue = lowerWorkerServer.getTopRowCell(neighbourCellColumn);
                        } else {
                            //cell belongs to current worker
                            neighbourCellValue =
                                    *(subgridCurrentGeneration + neighbourCellRow*rows + neighbourCellColumn);
                        }
                        //if it hasn't kicked the bucket yet, increment the counter
                        if(neighbourCellValue == ALIVE_CELL) ++liveNeighbouringCells;
                    } //end of for loop

                    //we got the number of alive neighbour cells
                    //now we just have to compute the value of the
                    //cell in the next generation
                    ubyte nextGenerationCellValue =
                            getCellNextGenerationValue(currentGenerationCellValue, liveNeighbouringCells);
                    //putting its value in the next generation subgrid
                    *(subgridNextGeneration + rows*currentRowComputing + currentColumnComputing) =
                            nextGenerationCellValue;
                    //increase the counter of live cells in next generation if applicable
                    if(nextGenerationCellValue == ALIVE_CELL) ++numberOfLiveCellsInNextGeneration;

                    //figure out which cell is next
                    if(currentRowComputing == rows-1 && currentColumnComputing == columns-1) {
                        //were done with this generation, evolution complete
                        finishedEvolution = true;
                        ++numberOfEvolutions;
                        numberOfLiveCellsInCurrentGeneration = numberOfLiveCellsInNextGeneration;
                        //cleverly moving the memory of the next generation
                        //onto the one of the current generation
                        ubyte *temp = subgridCurrentGeneration;
                        subgridCurrentGeneration = subgridNextGeneration;
                        subgridNextGeneration = temp;
                        numberOfLiveCellsInNextGeneration = 0;

                    } else if(currentColumnComputing == columns-1){
                        ++currentRowComputing;
                        currentColumnComputing = 0;
                    } else {
                        ++currentColumnComputing;
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
                    printf("Worker: just chilling\n");
                }
                break;
        }
    }
}

//distributes the grid workload to the worker threads
void distributor(chanend gridInputChannel,
        chanend gridOutputChannel,
        chanend accelerometerInputChannel,
        client interface DistributorWorker distributorToWorkerInterface[])
{
    printf("Distributor: distributor started!\n");
    printf("Distributor: Now configuring workers...\n");
    for(ubyte i = 0; i < NUMBER_OF_WORKERS; ++i) {
        //all workers will get at least this number of rows to work with
        uint baseNumberOfRowsPerWorker = GRID_HEIGHT / NUMBER_OF_WORKERS;
        //the first extraRows number of workers will have one extra row to work with
        uint extraRows = GRID_HEIGHT % NUMBER_OF_WORKERS;
        uint currentWorkerRows = baseNumberOfRowsPerWorker;
        if(i < extraRows) ++currentWorkerRows;
        distributorToWorkerInterface[i].initialiseSubgrid(currentWorkerRows, GRID_WIDTH);
    }
    printf("Distributor: workers configured\n");
    printf("Starting to read input image with height: %d and width: %d\n", GRID_HEIGHT, GRID_WIDTH);
    for(int row = 0; row < GRID_HEIGHT; ++row) {
        for(int column = 0; column < GRID_WIDTH; ++column) {
            uchar currentCellValue;
            gridInputChannel :> currentCellValue;  //read the current pixel value
            ubyte cellState = (currentCellValue == 255) ? ALIVE_CELL : DEAD_CELL;
            printf("%d", cellState);
        }
    }

  printf( "\nOne processing round completed...\n" );
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
        on tile[0]: DataInStream(infname, c_inIO);          //thread to read in a PGM image
        on tile[0]: DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
        on tile[0]: distributor(c_inIO, c_outIO, c_control, distributorToWorkerInterface);//thread to coordinate work
        par(ubyte i = 0; i < WRKRS; ++i)
            //ubyte upperWorker = (i == 0) ? NUMBER_OF_WORKERS-1 : i-1;
            //ubyte lowerWorker = (i == NUMBER_OF_WORKERS-1) ? 0 : i+1;
            on tile[1]: worker(distributorToWorkerInterface[i],
                workerToWorkerInterface[i][0],
                workerToWorkerInterface[i][1],
                workerToWorkerInterface[(i == 0) ? WRKRS-1 : i-1][1],
                workerToWorkerInterface[(i == WRKRS-1) ? 0 : i+1][0]);
      }

    return 0;
}
