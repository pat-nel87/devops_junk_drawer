#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kthread.h>
#include <linux/semaphore.h>
#include <linux/mutex.h>
#include <linux/slab.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/cred.h>
#include <linux/delay.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Patrick Nelson");
MODULE_DESCRIPTION("Producer Consumer Zombie Hunter Module for CSE 330 Project 2");

static int prod = 1;
module_param(prod, int, 0);
MODULE_PARM_DESC(prod, "number of producer threads");

static int cons = 1;
module_param(cons, int, 0);
MODULE_PARM_DESC(cons, "number of consumer threads");

static int size = 3;
module_param(size, int, 0);
MODULE_PARM_DESC(size, "size of buffer");

static int uid = 1000;
module_param(uid, int, 0);
MODULE_PARM_DESC(uid, "user id");

static struct task_struct **shared_state_buffer;
static int shared_state_buffer_in;
static int shared_state_buffer_out;

static struct semaphore empty_semaphore;
static struct semaphore full_semaphore;
static struct mutex buffer_mutex;

static struct task_struct *producer_task;
static void producer_process_scan(const char *producer_name_buffer);
static struct task_struct **consumer_task_pointer_array;

static int consumer_kthread_func(void *arg);
static int producer_kthread_func(void *arg);

static int __init producer_consumer_init(void)
{
	shared_state_buffer = kcalloc(size, sizeof(*shared_state_buffer), GFP_KERNEL);

	if (shared_state_buffer == NULL)
	{
		printk(KERN_ERR "Shared State Buffer failed to initialize!\n");
		return -ENOMEM;
	}

	consumer_task_pointer_array = kcalloc(cons, sizeof(*consumer_task_pointer_array), GFP_KERNEL);
	if (consumer_task_pointer_array == NULL)
	{
		printk(KERN_ERR "Consumer Task Pointer array failed to initialize!\n");
		return -ENOMEM;
	}

	sema_init(&empty_semaphore, size);
	sema_init(&full_semaphore, 0);
	mutex_init(&buffer_mutex);

	if (prod >= 1)
	{
		producer_task = kthread_run(producer_kthread_func, (void *)&producer_task, "Producer-1");
		if (IS_ERR(producer_task))
		{
			int error = PTR_ERR(producer_task);
			printk(KERN_ERR "Failed to create Producer Thread %d\n", error);
			producer_task = NULL;
		}
	}
	for (int i = 0; i < cons; i++)
	{
		consumer_task_pointer_array[i] = kthread_run(consumer_kthread_func, (void *)&consumer_task_pointer_array[i], "Consumer-%d", i + 1);
		if (IS_ERR(consumer_task_pointer_array[i]))
		{
			int error = PTR_ERR(consumer_task_pointer_array[i]);
			printk(KERN_ERR "Failed to create Consumer Thread %d\n", error);
			consumer_task_pointer_array[i] = NULL;
			break;
		}
	}

	return 0;
}

static void __exit producer_consumer_exit(void)
{
	up(&empty_semaphore);
	for (int i = 0; i < cons; i++)
	{
		up(&full_semaphore);
	}

	if (producer_task)
	{
		kthread_stop(producer_task);
	}

	for (int i = 0; i < cons; i++)
	{
		if (consumer_task_pointer_array[i])
		{
			kthread_stop(consumer_task_pointer_array[i]);
		}
	}

	kfree(shared_state_buffer);
	kfree(consumer_task_pointer_array);
}

static int consumer_kthread_func(void *arg)
{
	struct task_struct *zombie_thread;
	struct task_struct *local_consumer_task = *((struct task_struct **)arg);
	char consumer_name_buffer[TASK_COMM_LEN] = {0};
	get_task_comm(consumer_name_buffer, local_consumer_task);
	while (1)
	{
		if (down_interruptible(&full_semaphore) != 0)
		{
			if (kthread_should_stop())
			{
				break;
			}
			continue;
		}
		if (kthread_should_stop())
		{
			break;
		}
		mutex_lock(&buffer_mutex);
		zombie_thread = shared_state_buffer[shared_state_buffer_out];
		shared_state_buffer_out = (shared_state_buffer_out + 1) % size;
		mutex_unlock(&buffer_mutex);

		if (!zombie_thread) { continue; }

		up(&empty_semaphore);
		printk(KERN_INFO "[%s] has consumed a zombie process with pid %d and parent pid %d\n", consumer_name_buffer, zombie_thread->pid, zombie_thread->parent->pid);
	}
	return 0;
}

static void producer_process_scan(const char *producer_name_buffer)
{

	struct task_struct *ts;
	for_each_process(ts)
	{
		if (kthread_should_stop())
		{
			break;
		}
		if (ts->cred->uid.val != uid)
		{
			continue;
		}
		if (ts->exit_state & EXIT_ZOMBIE)
		{
			if (down_interruptible(&empty_semaphore) != 0)
			{
				if (kthread_should_stop())
				{
					break;
				}
				continue;
			}
			if (kthread_should_stop())
			{
				break;
			}
			mutex_lock(&buffer_mutex);
			shared_state_buffer[shared_state_buffer_in] = ts;
			shared_state_buffer_in = (shared_state_buffer_in + 1) % size;
			mutex_unlock(&buffer_mutex);
			up(&full_semaphore);
			printk(KERN_INFO "[%s] has produced a zombie process with pid %d and parent pid %d\n", producer_name_buffer, ts->pid, ts->parent->pid);
		}
	}
}

static int producer_kthread_func(void *arg)
{

	struct task_struct *local_producer_task = *((struct task_struct **)arg);
	char producer_name_buffer[TASK_COMM_LEN] = {0};
	get_task_comm(producer_name_buffer, local_producer_task);
	while (1)
	{
		if (kthread_should_stop())
		{
			break;
		}
		producer_process_scan(producer_name_buffer);
		msleep(100);
	}

	return 0;
}

module_init(producer_consumer_init);
module_exit(producer_consumer_exit);
