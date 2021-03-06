#pragma once
#include "shared.cuh"

namespace cuda
{
	enum target_id
	{
		host,
		gpu
	};

	static void memset_d( void* dst, int value, size_t size ) { CU_WRAP( cudaMemset( dst, value, size ) ); }
	static void memcpy_d2d( void* dst, const void* src, size_t size ) { CU_WRAP( cudaMemcpy( dst, src, size, cudaMemcpyDeviceToDevice ) ); }
	static void memcpy_h2d( void* dst, const void* src, size_t size ) { CU_WRAP( cudaMemcpy( dst, src, size, cudaMemcpyHostToDevice ) ); }
	static void memcpy_d2h( void* dst, const void* src, size_t size ) { CU_WRAP( cudaMemcpy( dst, src, size, cudaMemcpyDeviceToHost ) ); }

	template<typename T>
	struct shared_ptr_t
	{
		int* ref_cnt = nullptr;
		T* host = nullptr;
		T* dev = nullptr;
		size_t count = 0;

		shared_ptr_t( size_t count ) : count( count )
		{
			// Initialize reference count as 1 and allocate two arrays
			ref_cnt = new int( 1 );

			// Allocate memory both at host and the device
			size_t num_bytes = count * sizeof(T);
			CU_WRAP( cudaMalloc( ( void** ) &dev, num_bytes ) );
			CU_WRAP( cudaHostAlloc( ( void** ) &host, num_bytes, 0 ) );

			// Call default initializer and update device memory
			new ( host ) T[ num_bytes / sizeof( T ) ];
			update_device();
		}

		shared_ptr_t( shared_ptr_t& other )
		{
			// Increment reference count
			other.ref_cnt[ 0 ]++;

			// Copy all data
			ref_cnt = other.ref_cnt;
			host = other.host;
			dev = other.dev;
			count = other.count;
		}

		~shared_ptr_t()
		{
			// If reference count reaches 0 free all arrays
			if ( --ref_cnt[ 0 ] <= 0 )
			{
				delete ref_cnt;
				CU_WRAP( cudaFree( dev ) );
				CU_WRAP( cudaFreeHost( host ) );
			}
		}

		// Indexing using [] or -> will index into host array
		T& operator[]( size_t i ) { return host[ i ]; }
		T* operator->() { return host; }

		// Indexing using () will index into dev array and operator! decays the object into a dev pointer
		__device__ __host__ T& operator()( size_t i ) { return dev[ i ]; }
		T* operator!() { return dev; }

		// Copies all memory from host to device
		void update_device() { memcpy_h2d( dev, host, count * sizeof( T ) ); }

		// Copies all memory from device to host
		void update_host() { memcpy_d2h( host, dev, count * sizeof( T ) ); }

		// Syntax sugar for update_host() and update_device()
		void operator>>( target_id m ) { return m == target_id::gpu ? update_device() : update_host(); }
		void operator<<( target_id m ) { return m == target_id::gpu ? update_host() : update_device(); }
	};
};