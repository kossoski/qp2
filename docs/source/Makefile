ifndef QP_ROOT  
$(error "QP_ROOT is not defined. Source quantum_package.rc")
endif

default:
	./auto_generate.py
	make -C ../ html
	rm -rf ../build/man/
	make -C ../ man
	cp -r ../build/man/* $(QP_ROOT)/man/
clean:
	make -C ../ clean
	rm modules/*.rst
