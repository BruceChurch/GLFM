from cython_gsl cimport *
import cython
#from libc.stdlib cimport malloc, free
from cymem.cymem cimport Pool

# import both numpy and the Cython declarations for numpy
import numpy as np
cimport numpy as np

#cdef extern from "gsl/gsl_sf_exp.h":
#    double gsl_sf_exp(const double x)

# declare the interface to the C code
#cdef extern void c_multiply (double* array, double value, int m, int n)
cdef extern from "stdio.h":
    int tolower(int c)

cdef extern from "InferenceFunctions.h":
    #void IBPsampler_toy(double missing, gsl_matrix* X, char *C, gsl_matrix* Z,\
    #                gsl_matrix **B)
    int IBPsampler_func (double missing, gsl_matrix *X, char *C, gsl_matrix *Z, gsl_matrix **B, gsl_vector **theta, int *R, double *w, int maxR, int bias, int N, int D, int K, double alpha, double s2B, double s2Y,int maxK,int Nsim)

@cython.boundscheck(False)
@cython.wraparound(False)
def wrapper_IBPsampler(np.ndarray[double, ndim=2, mode="fortran"] input not None,\
        Cin, np.ndarray[double, ndim=2, mode="fortran"] Zin not None, int bias=1,\
        double s2Y=1.0, double s2B=1.0, double alpha=1.0, int Nsim=50,\
        int maxK=10, double missing=-1):#\
    """
    """
    #print input_in.flags['C_CONTIGUOUS']
    #input_in = np.ascontiguousarray(input_in)
    #print input_in.flags['C_CONTIGUOUS']

    # cdef gsl_matrix * B = gsl_matrix_alloc(dim, m)
    cdef int N, D, K
    cdef gsl_matrix_view Xview, Zview
    cdef gsl_matrix* X
    cdef gsl_matrix* Zm

    #N, D = input.shape[0], input.shape[1]
    #K = Zin.shape[0]
    N, D = input.shape[1], input.shape[0]
    K = Zin.shape[0]
    print 'N=%d, D=%d, K=%d\n' % (N, D, K)
    print input
    print Zin

    ## transpose input matrices in order to be able to call inner C function
    #cdef np.ndarray[double, ndim=2, mode="c"] input = input_in.transpose()
    #cdef np.ndarray[double, ndim=2, mode="c"] Zin = Zin_in.transpose()

    if len(Cin) != D:
        raise Exception('Size of C and X are not consistent!')
    #print 'size of C = 1*%d' % len(C)

    Xview = gsl_matrix_view_array(&input[0,0],D,N) #N,D)
    X = &Xview.matrix

    Zview = gsl_matrix_view_array(&Zin[0,0], K,N)
    Zm = &Zview.matrix # we need to allocate input matrix Z to [maxK*N] matrix
    cdef gsl_matrix* Z = gsl_matrix_calloc(maxK,N)
    for i in xrange(N):
        for k in xrange(K):
             gsl_matrix_set (Z, k, i,gsl_matrix_get (Zm, k, i))

    #B = <gsl_matrix **>malloc(sizeof(gsl_matrix*));
    cdef Pool mem = Pool()
    cdef gsl_matrix** B = <gsl_matrix**>mem.alloc(D, sizeof(gsl_matrix*));
    cdef gsl_vector** theta = <gsl_vector**>mem.alloc(D, sizeof(gsl_vector*));

    ##...............BODY CODE.......................##

    C = ''
    for d in xrange(D):
        C += chr( tolower(ord(Cin[d])) ) # convert to lower case

    cdef np.ndarray[np.int32_t, ndim=1, mode="c"] R = np.empty(D,dtype=np.int32)
    cdef np.ndarray[double, ndim=1, mode="c"] w = np.empty(D)
    cdef np.ndarray[double, ndim=1] maxX = np.empty(D)
    cdef int maxR = 1
    #print 'Size of R[D]=(%d,%d)' % (R.shape[0],R.shape[1])
    #print 'Size of w[D]=(%d,%d)' % (w.shape[0],w.shape[1])
    #print 'Size of maxX[D]=(%d,%d)' % (maxX.shape[0],maxX.shape[1])
    #R[0] = 0; R[1] = 1; R[2] = 2; R[221] = 3
    #print 'R[0]=%d, R[1]=%d, R[2]=%d, R[3]=%d\n' % (R[0], R[1], R[2], R[221])

    cdef gsl_vector_view Xd_view
    for d in xrange(D):
        Xd_view = gsl_matrix_row(X,d)
        maxX[d] = gsl_vector_max(&Xd_view.vector)
        R[d] = 1
        w[d] = 1
        if C[d] == 'g':
            B[d] = gsl_matrix_alloc(maxK,1)
        elif C[d] == 'p':
            B[d] = gsl_matrix_alloc(maxK,1)
            w[d]=2/maxX[d]
        elif C[d] == 'n':
            B[d] = gsl_matrix_alloc(maxK,1)
            w[d] = 2/maxX[d]
        elif 'c':
            R[d] = <int>maxX[d]
            B[d] = gsl_matrix_alloc(maxK,R[d])
            if (R[d] > maxR):
                maxR = R[d]
        elif 'o':
            R[d] = <int>maxX[d];
            B[d] = gsl_matrix_alloc(maxK,1)
            theta[d] = gsl_vector_alloc(R[d])
            if (R[d] > maxR):
                maxR = R[d]

    ##...............Inference Function.......................##
    print 'Entering C function'
    cdef int Kest = IBPsampler_func(missing, X, C, Z, B, theta,\
            <int*> R.data, &w[0],\
            maxR, bias,  N, D, K, alpha, s2B, s2Y, maxK, Nsim);
    print 'Back to Python'

    ##...............Set Output Pointers.......................##
    cdef np.ndarray[double, ndim=2] Z_out = np.zeros((Kest,N))
    cdef np.ndarray[double, ndim=3] B_out = np.zeros((D,Kest,maxR))
    cdef np.ndarray[double, ndim=2] Theta_out = np.zeros((D,maxR))
    #cdef np.ndarray[np.int32_t, ndim=1] result = np.zeros((len(arg)), dtype =
    #        np.int32)
    print "Kest=%d, N=%d" % (Kest,N)

    # #Zview = gsl_matrix_submatrix(Z, 0, 0, Kest, N)
    #print 'N=%d, K=%d, Kest=%d' % (N,K,Kest)
    for i in xrange(N):
        for k in xrange(Kest):
            #print 'k=%d, i=%d' % (k,i)
            Z_out[k,i] = gsl_matrix_get(Z,k,i)
            #Z_out[k,i] = (&Zview.matrix)->data[k*N+i]

    cdef gsl_matrix_view Bd_view
    cdef gsl_matrix* BT
    for d in xrange(D):
        Bd_view =  gsl_matrix_submatrix(B[d], 0, 0, Kest, R[d])
        BT = gsl_matrix_alloc(R[d],Kest)
        gsl_matrix_transpose_memcpy (BT, &Bd_view.matrix)
        for k in xrange(Kest):
            for i in xrange(maxR):
                B_out[d,k,i] = gsl_matrix_get(BT,k,i)
        gsl_matrix_free(BT)

    for d in xrange(D):
        for i in xrange(maxR):
            if (C[d]=='o' and i<R[d]):
                Theta_out[d,i] = gsl_vector_get(theta[d],i)


    ##..... Free memory.....##
    for d in xrange(D):
        gsl_matrix_free(B[d])
        gsl_vector_free(theta[d])
    gsl_matrix_free(Z)
    #free(B)
    #free(theta)

    return (Z_out,B_out,Theta_out)
