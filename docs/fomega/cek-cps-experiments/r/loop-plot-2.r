title <- "Loop (time)"

masterdata <- read.table("master-times-Loop", header=T)
recdata  <- read.table("recursive-times-Loop", header=T)
cpsdata <- read.table("cps-times-Loop", header=T)
origdata <- read.table("orig-times-Loop", header=T)

all <-  c(recdata$usr+recdata$sys, cpsdata$usr+cpsdata$sys, origdata$usr+origdata$sys)
ylim <- c(min(all), max(all))

start <- function(fr,col) {  
    plot  (fr$n,fr$usr+fr$sys, col=col, pch=20, main=title, xlab = "n", ylab = "Time (s)", ylim=ylim)
    lines (fr$n,fr$usr+fr$sys, col=col, pch=20)
}

draw <- function(fr,col) {
    points (fr$n,fr$usr+fr$sys, col=col, pch=20)
    lines  (fr$n,fr$usr+fr$sys, col=col, pch=20)
}

mastercol="gold"
reccol="darkolivegreen3"
cpscol="blue"
origcol="darkmagenta"

start  (recdata, reccol)
draw  (cpsdata, cpscol)
draw  (origdata, origcol)

    
legend(x="topleft", inset=.05, legend=c("recursive", "CPS", "Original CEK machine"), col=c(reccol, cpscol, origcol), lty=1, lw=2)
