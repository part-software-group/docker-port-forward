مقدمه
=====

این اسکریپت برای اتصال به یک یا چند پورت خاص کانتینرها بدون تغییر در ساختار یا rebuild کردن برای باز کردن پورت می‌باشد.


نیازمندی‌ها
===========

* docker


طریق استفاده
============

برای استفاده به صورت زیر عمل می‌کنید:

```/bin/bash
> /bin/bash dockerPortForward.sh --help
Run docker debug for node js app

Usage:
  bash dockerPortForward.sh [OPTIONS...] CONTAINER

Options:
  -p, --port=public-port:private-port
  -v, --version
  -h, --help

Examples:
> bash dockerPortForward.sh -p 5858:35858 container-name
> bash dockerPortForward.sh -p 5858-5860:35858-35860 container-name
> bash dockerPortForward.sh -p 5858-5860:35858-35860 -p 9229:3229 container-name
```


### container

نام کانتینر داکر برای اتصال و debug


### port (options)

پورت برای اتصال، دارای دو بخش است:

* public: پورت برای اتصال خارجی

* private: پورت داخلی برای فوروارد کردن


تست
===

برای تست به صورت زیر عمل کنید:


۱. ابتدا یک image مثلا postgres را به صورت container اجرا کنید:

```/bin/bash
> docker run --rm -it --name postgres-test docker.loc:5000/postgres:10.2
```


۲. سپس اسکریپت را به صورت زیر اجرا می‌کنید:

```/bin/bash
> bash dockerPortForward.sh postgres-test -p 9090:5432
```


۳. حال می‌توان با `psql` یا هر درایور دیگری به پورت **9090** وصل شد.